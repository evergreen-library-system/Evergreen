dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.Dialog');
dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.NumberSpinner');
dojo.require('openils.Event');
dojo.require('openils.acq.Picklist');
dojo.require('openils.acq.Lineitem');
dojo.require('openils.User');
dojo.require('openils.Util');

var searchFields = [];
var resultPicklist;
var resultLIs;
var selectedLIs;
var recvCount = 0;
var sourceCount = 0; // how many sources are we searching
var user = new openils.User();
var searchLimit = 10;
var liCache = {};

function drawForm() {
    fieldmapper.standardRequest(
        ['open-ils.search', 'open-ils.search.z3950.retrieve_services'], 
        {   async: true,
            params: [user.authtoken],
            oncomplete: _drawForm
        }
    );
}

function _drawForm(r) {

    var sources = openils.Util.readResponse(r);
    if(!sources) return;

    for(var name in sources) {
        source = sources[name];
        if(name == 'native-evergreen-catalog') continue;
        bibSourceSelect.addOption({value:name, label:source.label});
        for(var attr in source.attrs) 
            if(!attr.match(/^#/)) // xml comment nodes
                searchFields.push(source.attrs[attr]);
    }

    searchFields = searchFields.sort(
        function(a,b) {
            if(a.label < b.label) 
                return -1;
            if(a.label > b.label) 
                return 1;
            return 0;
        }
    );

    var tbody = dojo.byId('oils-acq-search-fields-tbody');
    var tmpl = tbody.removeChild(dojo.byId('oils-acq-search-fields-template'));

    for(var f in searchFields) {
        var field = searchFields[f];
        if(dijit.byId('text_input_'+field.name)) continue;
        var row = tmpl.cloneNode(true);
        tbody.insertBefore(row, dojo.byId('oils-acq-seach-fields-count-row'));
        var labelCell = dojo.query('[name=label]', row)[0];
        var inputCell = dojo.query('[name=input]', row)[0];
        labelCell.appendChild(document.createTextNode(field.label));
        input = new dijit.form.TextBox({name:field.name, label:field.label, id:'text_input_'+field.name});
        inputCell.appendChild(input.domNode);
    }
}

function clearSearchForm() {
    for(var f in searchFields) {
        var field = searchFields[f];
        dijit.byId('text_input_'+field.name).setValue('');
    }
}

function doSearch(values) {
    dojo.style('oils-acq-pl-loading', 'visibility', 'visible');

    search = {
        service : [],
        username : [],
        password : [],
        search : {},
        limit : values.limit,
        offset : searchOffset
    };
    searchLimit = values.limit;
    delete values.limit;

    var selected = bibSourceSelect.getValue();
    for(var i = 0; i < selected.length; i++) {
        search.service.push(selected[i]);
        search.username.push('');
        search.password.push('');
        sourceCount++;
    }

    for(var v in values) {
        if(values[v]) {
            var input = dijit.byId('text_input_'+v);
            search.search[v] = values[v];
        }
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.search.z3950'],
        {   async: true,
            params: [user.authtoken, search, null, {respond_li:1, flesh_attrs:1, clear_marc:1}],
            onresponse: handleResult,
        }
    );
}

function setRowAttr(row, liWrapper, field) {
    var val = liWrapper.findAttr(field, 'lineitem_marc_attr_definition') || '';
    dojo.query('[name='+field+']', row)[0].appendChild(document.createTextNode(val));
}

var resultRow;
function handleResult(r) {
    var result = openils.Util.readResponse(r);
    dojo.style('oils-acq-pl-search-results', 'display', 'block');
    dojo.style('oils-acq-search-block', 'display', 'none');

    var tbody = dojo.byId('plist-tbody');
    if(!resultRow) 
        resultRow = tbody.removeChild(dojo.byId('plist-row')); 

    if(result.lineitem) {
        var li = result.lineitem;
        liCache[li.id()] = li;
        var liWrapper = new openils.acq.Lineitem({lineitem:li});
        var row = resultRow.cloneNode(true);
        var tds = dojo.query('[name]', row);
        dojo.forEach(tds, function(td) {setRowAttr(row, liWrapper, td.getAttribute('name'));});
        tbody.appendChild(row);
    }
}


function showPlForm() {
    dojo.style('oils-acq-pl-search-results', 'display', 'none');
    dojo.style('oils-acq-search-block', 'display', 'block');
    dojo.style('oils-acq-pl-loading', 'visibility', 'hidden');
}

function loadPLSelect() {
    var plList = [];
    function handleResponse(r) {
        plList.push(r.recv().content());
    }
    var method = 'open-ils.acq.picklist.user.retrieve';
    fieldmapper.standardRequest(
        ['open-ils.acq', method],
        {   async: true,
            params: [openils.User.authtoken],
            onresponse: handleResponse,
            oncomplete: function() {
                plAddExistingSelect.store = 
                    new dojo.data.ItemFileReadStore({data:acqpl.toStoreData(plList)});
                plAddExistingSelect.setValue();
            }
        }
    );
}


function saveResults(values) {
    selectedLIs = resultLIs;

    if(values.which == 'selected') {
        selectedLIs = [];
        var selected = plResultGrid.selection.getSelected();
        for(var idx = 0; idx < selected.length; idx++) {
            var rowIdx = selected[idx];
            var id = plResultGrid.model.getRow(rowIdx).id;
            for(var i = 0; i < resultLIs.length; i++) {
                var pl = resultLIs[i];
                if(pl.id() == id) {
                    selectedLIs.push(pl);
                }
            }
        }
    }
        
    if(values.new_name && values.new_name != '') {
        // save selected lineitems to a new picklist
        if(values.which = 'selected') {
            openils.acq.Picklist.create(
                {name: values.new_name}, 
                function(id) {
                    updateLiList(id, selectedLIs, 0, 
                        function(){location.href = 'view/' + id});
                }
            );
        }  else {
            // save all == change the name of the results picklist
            resultPicklist.name(values.new_name); 
            openils.acq.Picklist.update(resultPicklist,
                function(stat) {
                    location.href = 'view/' + resultPicklist.id(); 
                }
            );
        }
    } else if(values.existing_pl) {
        // update lineitems to use an existing picklist
        updateLiList(values.existing_pl, selectedLIs, 0, 
            function(){location.href = 'view/' + values.existing_pl});
    }
}

function updateLiList(pl, list, idx, oncomplete) {
    if(idx >= list.length)
        return oncomplete();
    var li = selectedLIs[idx];
    li.picklist(pl);
    new openils.acq.Lineitem({lineitem:li}).update(
        function(r) {
            updateLiList(pl, list, ++idx, oncomplete);
        }
    );
}

openils.Util.addOnLoad(drawForm);

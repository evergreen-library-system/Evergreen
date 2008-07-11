dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.NumberSpinner');
dojo.require('openils.Event');
dojo.require('openils.acq.Picklist');
dojo.require('openils.acq.Lineitems');
dojo.require('openils.User');

var searchFields = [];
var resultPicklist;
var resultLIs;
var selectedLIs;
var recvCount = 0;
var sourceCount = 0; // how many sources are we searching
var user = new openils.User();
var searchLimit = 10;

function drawForm() {

    var sources = fieldmapper.standardRequest(
        ['open-ils.search', 'open-ils.search.z3950.retrieve_services'], 
        [user.authtoken]
    );

    openils.Event.parse_and_raise(sources);

    for(var name in sources) {
        source = sources[name];
        bibSourceSelect.addOption(name, name+':'+source.host);
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

function doSearch(values) {
    dojo.style('searchProgress', 'visibility', 'visible');
    searchProgress.update({progress: 0});

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
            params: [user.authtoken, search],
            onresponse: handleResult,
        }
    );
}

function handleResult(r) {
    var result = r.recv().content();
    if(openils.Event.parse(result)) {
        alert(openils.Event.parse(result));
        dojo.style('searchProgress', 'visibility', 'hidden');
        return;
    }
    if(result.complete)
        return viewResults(result.picklist_id);
    searchProgress.update({maximum: result.total, progress: result.progress});
}

function viewResults(plId) {
    var plist = new openils.acq.Picklist(plId,
        function(model) {
            resultLIs = plist._items;
            dojo.style('oils-acq-pl-search-results', 'visibility', 'visible');
            JUBGrid.populate(plResultGrid, model, plist._items);
        },
        {flesh_attrs:1, clear_marc:1, limit: searchLimit}
    );
    resultPicklist = plist._plist;
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
        // XXX create a new PL and copy LIs over
        /*
        if(values.which = 'selected') {
            resultPicklist = new acqpl();
            resultPicklist.owner(user.user.id())
        } 
        */
        resultPicklist.name(values.new_name); 
        openils.acq.Picklist.update(resultPicklist,
            function(stat) {
                location.href = 'view/' + resultPicklist.id(); 
            }
        );
    } else if(values.existing_pl) {
        updateLiList(values.existing_pl, selectedLIs, 0, 
            function(){location.href = 'view/' + values.existing_pl});
    }
}

function updateLiList(pl, list, idx, oncomplete) {
    if(idx >= list.length)
        return oncomplete();
    var li = selectedLIs[idx];
    li.picklist(pl);
    new openils.acq.Lineitems({lineitem:li}).update(
        function(r) {
            updateLiList(pl, list, ++idx, oncomplete);
        }
    );
}

dojo.addOnLoad(drawForm);

dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.NumberSpinner');
dojo.require('openils.Event');
dojo.require('openils.acq.Picklist');

var searchFields = [];
var resultPicklist;
var recvCount = 0;
var sourceCount = 0; // how many sources are we searching
var user = new openils.User();

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
        //tbody.appendChild(row);
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
            dojo.style('oils-acq-pl-search-results', 'visibility', 'visible');
            JUBGrid.populate(plResultGrid, model, plist._items);
            dojo.style('oils-acq-lineitem-details-grid', 'visibility', 'hidden');
        }
    );
    resultPicklist = plist._plist;
}

function saveResults(values) {
    if(!values.name) return;
    resultPicklist.name(values.name); 
    openils.acq.Picklist.update(resultPicklist,
        function(stat) {
            location.href = 'view/' + resultPicklist.id(); 
        }
    );
}

dojo.addOnLoad(drawForm);

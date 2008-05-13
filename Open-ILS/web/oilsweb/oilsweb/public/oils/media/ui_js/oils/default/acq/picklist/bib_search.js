dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('openils.Event');

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

    //alert(dojo.query('[name=label]', 'oils-acq-search-fields-template'));
    var tbody = dojo.byId('oils-acq-search-fields-tbody');
    var tmpl = tbody.removeChild(dojo.byId('oils-acq-search-fields-template'));

    for(var f in searchFields) {
        var field = searchFields[f];
        if(dijit.byId('text_input_'+field.name)) continue;
        var row = tmpl.cloneNode(true);
        tbody.appendChild(row);
        var labelCell = dojo.query('[name=label]', row)[0];
        var inputCell = dojo.query('[name=input]', row)[0];
        labelCell.appendChild(document.createTextNode(field.label));
        input = new dijit.form.TextBox({name:field.name, label:field.label, id:'text_input_'+field.name});
        inputCell.appendChild(input.domNode);
    }
}

function doSearch(values) {
    dojo.style('searchProgress', 'visibility', 'visible');

    search = {
        service : [],
        username : [],
        password : [],
        search : {},
        limit : searchLimit,
        offset : searchOffset
    }

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
        ['open-ils.search', 'open-ils.search.z3950.search_class'],
        {   async: true,
            params: [user.authtoken, search],
            onresponse: handleResult,
            oncomplete: viewPicklist
        }
    );
}

function handleResult(r) {
    var result = r.recv().content();
    if(!resultPicklist)
        createResultPicklist();

    searchProgress.update({maximum: sourceCount*searchLimit+1, progress: ++recvCount});

    for(var idx in result.records) {
        searchProgress.update({progress: ++recvCount});
        var rec = result.records[idx];
        var lineitem =  new jub()

        lineitem.picklist(resultPicklist.id());
        lineitem.source_label(result.service)
        lineitem.marc(rec.marcxml)
        lineitem.eg_bib_id(rec.bibid)

        var id = fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.create'],
            [user.authtoken, lineitem]
        );
    }
}

function createResultPicklist() {
    resultPicklist = new acqpl();
    resultPicklist.name('');
    resultPicklist.owner(user.user.id());

    /* delete the old picklist with name = '' */
    var pl = fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.name.retrieve'],
        [user.authtoken, '']
    );

    if(pl) {
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.picklist.delete'],
            [user.authtoken, pl.id()]
        );
    }

    resultPicklist.id(
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.picklist.create'],
            [user.authtoken, resultPicklist]
        )
    );
}

dojo.addOnLoad(drawForm);

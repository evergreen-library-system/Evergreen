dojo.require('dijit.form.FilteringSelect');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('fieldmapper.IDL');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoGrid');

function updateFieldSelector() {
    var cls = this.attr('value');
    if(!cls) return;
    var flist = fieldmapper.IDL.fmclasses[cls];
    var fields = [];
    for(var f in flist.fields) {
        var field = flist.fields[f];
        if(field.virtual) continue;
        fields.push({name:field.label, value:field.name});
    }
    fdocGrid.overrideEditWidgets.field.store = new dojo.data.ItemFileReadStore(
        {data:{identifier:'value', label:'name', items:fields}});
}

function load() {
    var slist = fieldmapper.IDL.fmclasses;
    var dlist = [];

    fdocGrid.overrideEditWidgets.field = editFieldSelector;
    fdocGrid.overrideEditWidgets.fm_class = editClassSelector;
    dojo.connect(fdocGrid.overrideEditWidgets.fm_class, 'onChange', updateFieldSelector);

    for(var f in slist) {
        if(slist[f].label != slist[f].name) // only show tables that have an actual label
            dlist.push({value:slist[f].name, name:slist[f].label});
    }
    dlist = dlist.sort(function(a, b){return (a.name < b.name) ? -1 : 1;});

    fmClassSelector.store = 
        fdocGrid.overrideEditWidgets.fm_class.store = 
            new dojo.data.ItemFileReadStore({data:{identifier:'value', label:'name', items:dlist}});

    fmClassSelector.startup();
    dojo.connect(fmClassSelector, 'onChange',
        function() {
            fdocGrid.resetStore();
            fdocGrid.loadAll({order_by:{fdoc : 'field'}}, {fm_class: this.attr('value')});
        }
    );
}


openils.Util.addOnLoad(load);


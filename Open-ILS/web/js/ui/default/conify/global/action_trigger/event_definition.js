dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.TextBox');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');


function loadEventDef() { 
    edGrid.loadAll({order_by:{atevdef : 'hook'}}); 
    edGrid.overrideEditWidgetClass.template = 'dijit.form.Textarea';
    dojo.connect(eventDefTabs,'selectChild', tabLoader);
}

var loadedTabs = {'tab-atevdef' : true};
function tabLoader(child) {
    if(loadedTabs[child.id]) return;
    loadedTabs[child.id] = true;
    switch(child.id) {
        case 'tab-atevparam': 
            tepGrid.loadAll({order_by:{atevparam : 'event_def'}}); 
            break;
        case 'tab-ath': 
            thGrid.loadAll({order_by:{ath : 'key'}}); 
            break;
        case 'tab-atenv': 
            teeGrid.loadAll({order_by:{atenv : 'event_def'}}); 
            break;
        case 'tab-atreact': 
            trGrid.loadAll({order_by:{atreact : 'module'}}); 
            break;
        case 'tab-atval': 
            tvGrid.loadAll({order_by:{atval : 'module'}}); 
            break;
        case 'tab-test': 
            loadTestTab();
            break;
    }
}

function loadTestTab() {
    var pcrud = new openils.PermaCrud();
    var hooks = pcrud.search('ath', {core_type : 'circ'});

    circTestHookSelector.store = new dojo.data.ItemFileReadStore({data : ath.toStoreData(hooks, 'key', {identifier:'key'})});
    circTestHookSelector.searchAttr = 'key';
    circTestHookSelector.startup();

    var defs = pcrud.search('atevdef', {hook : hooks.map(function(i){return i.key()})});
    circTestDefSelector.store = new dojo.data.ItemFileReadStore({data : atevdef.toStoreData(defs)});
    circTestDefSelector.searchAttr = 'id';
    circTestDefSelector.startup();

    dojo.connect(circTestHookSelector, 'onChange',
        function() {
            circTestDefSelector.query = {hook : this.attr('value')};
        }
    );
}

function evtTestCirc() {
    var def = circTestDefSelector.attr('value');
    var barcode = circTestBarcode.attr('value');
    if(!(def && barcode)) return;

    progressDialog.show();

    function handleResponse(r) {
        var evt = openils.Util.readResponse(r);
        progressDialog.hide();
        if(evt && evt != '0') {
            var output = evt.template_output();
            if(!output) output = evt.error_output();
            var pre = document.createElement('pre');
            pre.innerHTML = output.data();
            dojo.byId('test-event-output').appendChild(pre);
            openils.Util.show('test-event-output');
        }
    }

    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.trigger_event_by_def_and_barcode.fire'],
        {   async: true,
            params: [openils.User.authtoken, def, barcode],
            oncomplete: handleResponse
        }
    );
}

openils.Util.addOnLoad(loadEventDef);

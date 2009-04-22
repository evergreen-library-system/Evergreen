dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.TextBox');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');
dojo.requireLocalization('openils.conify', 'conify');

var localeStrings = dojo.i18n.getLocalization('openils.conify', 'conify');

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
    var defData = atevdef.toStoreData(defs);
    circTestDefSelector.store = new dojo.data.ItemFileReadStore({data : defData});
    circTestDefSelector.searchAttr = 'name';
    circTestDefSelector.startup();

    dojo.connect(circTestHookSelector, 'onChange',
        function() {
            circTestDefSelector.query = {hook : this.attr('value')};
        }
    );
}


function eventDefGetter(rowIdx, item) {
    if(!item) return '';
    var def = this.grid.store.getValue(item, 'event_def');
    return getDefName(def);
}

function getDefName(def) {

    if(typeof def != 'object') {
        edGrid.store.fetchItemByIdentity({
            identity : def,
            onItem : function(item) { def = new fieldmapper.atevdef().fromStoreItem(item); }
        });
    }

    return dojo.string.substitute(
        localeStrings.EVENT_DEF_LABEL, [
            fieldmapper.aou.findOrgUnit(def.owner()).shortname(), 
            def.name()
        ]);
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
            openils.Util.appendClear('test-event-output', pre);
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

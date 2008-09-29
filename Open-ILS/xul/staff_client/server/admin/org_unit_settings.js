dojo.require("dijit.layout.LayoutContainer");
dojo.require("dijit.layout.ContentPane");
dojo.require('dijit.form.FilteringSelect');
dojo.require("dojox.grid.Grid");
dojo.require("fieldmapper.Fieldmapper");
dojo.require("fieldmapper.dojoData");
dojo.require("fieldmapper.OrgUtils");
dojo.require('dojo.cookie');
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');

var authtoken;
var contextOrg;
var user;
var contextSelector;

function osInit(data) {
    authtoken = dojo.cookie('ses') || new openils.CGI().param('ses');
    user = new openils.User({authtoken:authtoken}).user;
    contextOrg = user.ws_ou();
    contextSelector = dojo.byId('os-context-selector');

    var names = [];
    for(var key in osSettings)
        names.push(key);

    fieldmapper.standardRequest(
        [   'open-ils.actor', 
            'open-ils.actor.ou_setting.ancestor_default.batch'],
        {   async: true,
            params: [contextOrg, names],
            oncomplete: function(r) {
                var data = r.recv().content();
                if(e = openils.Event.parse(data))
                    return alert(e);
                osLoadGrid(data);
            }
        }
    );
    buildMergedOrgSel(contextSelector, user.ws_ou(), 0);
    // open-ils.actor.user.get_work_ous.ids
}
dojo.addOnLoad(osInit);

function osChangeContect() {
    contextOrg = getSelectorVal(contextSelector);
}

function osLoadGrid(data) {
    var gridData = {items:[]}
    for(var key in data) {
        if(data[key]) {
            osSettings[key].context = data[key].org;
            osSettings[key].value = data[key].value;
        }
        gridData.items.push({name:key});
    }
    gridData.identifier = 'name';
    var store = new dojo.data.ItemFileReadStore({data:gridData});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{name:'*'}});

    osGrid.setModel(model);
    osGrid.setStructure(osGridLayout);
    osGrid.update();
}

function osGetGridData(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var value = osSettings[data.name][this.field];
    if(value == null) return '';
    switch(this.field) {
        case 'context':
            return fieldmapper.aou.findOrgUnit(value).shortname();
        default:
            return value;
    }
}

function osGetEditLink(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    return this.value.replace(/SETTING/, data.name);
}

function osLaunchEditor(name) {
}


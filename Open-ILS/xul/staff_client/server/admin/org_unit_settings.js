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
dojo.require('openils.widget.OrgUnitFilteringSelect');

var authtoken;
var contextOrg;
var user;
var workOrgs;

function osInit(data) {
    authtoken = dojo.cookie('ses') || new openils.CGI().param('ses');
    user = new openils.User({authtoken:authtoken}).user;
    contextOrg = user.ws_ou();

    fieldmapper.standardRequest(
        [   'open-ils.actor',
            'open-ils.actor.user.get_work_ous.ids'],
        {   async: true,
            params: [authtoken],
            oncomplete: function(r) {
                var list = r.recv().content();
                if(e = openils.Event.parse(list))
                    return alert(e);
                workOrgs = list;
                buildMergedOrgSelector(list);
            }
        }
    );

    osDraw();
}
dojo.addOnLoad(osInit);

function osDraw() {
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
}

function buildMergedOrgSelector(orgList) {
    var orgNodeList = [];
    for(var i = 0; i < orgList.length; i++) {
        // add the work org parents
        var parents = [];
        var node = fieldmapper.aou.findOrgUnit(orgList[i]);
        while(node.parent_ou() != null) {
            node = fieldmapper.aou.findOrgUnit(node.parent_ou());
            parents.push(node);
        }
        orgNodeList = orgNodeList.concat(parents.reverse());

        // add the work org children
        orgNodeList = orgNodeList.concat(
            fieldmapper.aou.descendantNodeList(orgList[i]));
    }

    var store = new dojo.data.ItemFileReadStore({data:aou.toStoreData(orgNodeList)});
    osContextSelector.store = store;
    osContextSelector.startup();
    osContextSelector.setValue(user.ws_ou());
}

function osChangeContext() {
    if(contextOrg == osContextSelector.getValue())
        return;
    contextOrg = osContextSelector.getValue();
    osDraw();
}

function osLoadGrid(data) {
    var gridData = {items:[]}
    for(var key in data) {
        var setting = osSettings[key];
        setting.context = null;
        setting.value = null;
        if(data[key]) {
            setting.context = data[key].org;
            setting.value = data[key].value;
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


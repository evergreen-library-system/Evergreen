dojo.require("dijit.layout.LayoutContainer");
dojo.require("dijit.layout.ContentPane");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.Dialog');
dojo.require("dojox.grid.Grid");
dojo.require("fieldmapper.Fieldmapper");
dojo.require("fieldmapper.dojoData");
dojo.require("fieldmapper.OrgUtils");
dojo.require('dojo.cookie');
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.PermaCrud');

var authtoken;
var contextOrg;
var user;
var workOrgs;
var osSettings = {};

function osInit(data) {
    authtoken = dojo.cookie('ses') || new openils.CGI().param('ses');
    user = new openils.User({authtoken:authtoken});
    contextOrg = user.user.ws_ou();

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
    var types = new openils.PermaCrud({authtoken:authtoken}).retrieveAll('coust');

    dojo.forEach(types, 
        function(type) {
            osSettings[type.name()] = {
                label : type.label(),
                desc : type.description(),
                type : type.datatype(),
                fm_class : type.fm_class()
            }
        }
    );
    
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

    var list = [];
    dojo.forEach(orgNodeList, function(item) {
        if(list.filter(function(i){return (i.id() == item.id())}).length == 0)
            list.push(item);
    });

    var store = new dojo.data.ItemFileReadStore({data:aou.toStoreData(list)});
    osContextSelector.store = store;
    osContextSelector.startup();
    osContextSelector.setValue(user.user.ws_ou());
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
    gridData.items = gridData.items.sort(
        function(a, b) {
            var seta = osSettings[a.name];
            var setb = osSettings[b.name];
            if(seta.label > setb.label) return 1;
            if(seta.label < setb.label) return -1;
            return 0;
        }
    );
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
    var setting = osSettings[data.name];
    var value = setting[this.field];
    if(value == null) return '';
    switch(this.field) {
        case 'context':
            return fieldmapper.aou.findOrgUnit(value).shortname();
        case 'label':
            if(setting.noInherit)
                return value + ' *';
            return value;
        case 'value':
            if(setting.type == 'bool') {
                if(value) 
                    return dojo.byId('os-true').innerHTML;
                return dojo.byId('os-false').innerHTML;
            }
        default:
            return value;
    }
}

function osGetEditLink(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    return data.name;
}

function osFormatEditLink(name) {
    return this.value.replace(/SETTING/, name);
}

function osLaunchEditor(name) {
    osEditDialog._osattr = name;
    osEditDialog.show();
    user.buildPermOrgSelector(
        ['UPDATE_ORG_UNIT_SETTING.' + name, 'UPDATE_ORG_UNIT_SETTING_ALL'],
        osEditContextSelector, osSettings[name].context
    );
    dojo.byId('os-edit-name').innerHTML = osSettings[name].label;
    dojo.byId('os-edit-desc').innerHTML = osSettings[name].desc || '';

    dojo.style(osEditTextBox.domNode, 'display', 'none');
    dojo.style(osEditCurrencyTextBox.domNode, 'display', 'none');
    dojo.style(osEditNumberTextBox.domNode, 'display', 'none');
    dojo.style(osEditBoolSelect.domNode, 'display', 'none');

    var widget;
    switch(osSettings[name].type) {
        case 'number':
            widget = osEditNumberTextBox; 
            break;
        case 'currency':
            widget = osEditCurrencyTextBox; 
            break;
        case 'bool':
            widget = osEditBoolSelect; 
            break;
        default:
            widget = osEditTextBox;
    }

    dojo.style(widget.domNode, 'display', 'block');
    widget.setValue(osSettings[name].value);
}

function osEditSetting(deleteMe) {
    osEditDialog.hide();
    var name = osEditDialog._osattr;

    var obj = {};
    if(deleteMe) {
        obj[name] = null;

    } else {

        switch(osSettings[name].type) {
            case 'number':
                obj[name] = osEditNumberTextBox.getValue();
                if(obj[name] == null) return;
                break;
            case 'currency':
                obj[name] = osEditCurrencyTextBox.getValue();
                if(obj[name] == null) return;
                break;
            case 'bool':
                var val = osEditBoolSelect.getValue();
                obj[name] = (val == 'true') ? true : false;
                break;
            default:
                obj[name] = osEditTextBox.getValue();
                if(obj[name] == null) return;
        }
    }

    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.org_unit.settings.update'],
        {   async: true,
            params: [authtoken, osEditContextSelector.getValue(), obj],
            oncomplete: function(r) {
                var res = r.recv().content();
                if(e = openils.Event.parse(res))
                    return alert(e);
                osDraw();
            }
        }
    );
}


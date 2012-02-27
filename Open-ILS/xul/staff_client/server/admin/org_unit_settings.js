dojo.require('fieldmapper.AutoIDL');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.ComboBox');
dojo.require('dojox.grid.Grid');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.dojoData');
dojo.require('fieldmapper.OrgUtils');
dojo.require('dojo.cookie');
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.widget.ProgressDialog');
dojo.require('dijit.Toolbar');
dojo.require('openils.XUL');

var authtoken;
var query;
var contextOrg;
var user;
var osSettings = {};
var ouSettingValues = {};
var ouSettingNames = {};
var ouNames = {};
var osEditAutoWidget;
var perm_codes = {};
var osGroups = {};
var searchAssist = [];
var pcrud;

function osInit(data) {
    showProcessingDialog(true);
    
    authtoken = new openils.CGI().param('ses') || dojo.cookie('ses');
    if(!authtoken && openils.XUL.isXUL()) {
        var stash = openils.XUL.getStash();
        authtoken = stash.session.key;
    }   
    query = new openils.CGI().param('filter');
    user = new openils.User({authtoken:authtoken});
    contextOrg = user.user.ws_ou();
    openils.User.authtoken = authtoken;
    
    pcrud = new openils.PermaCrud({authtoken:authtoken});
    
    var grps = pcrud.retrieveAll('csg');
    dojo.forEach(grps, function(grp) { osGroups[grp.name()] = grp.label(); });
    
    var connect = function() { 
        dojo.connect(contextOrg, 'onChange', osChangeContext); 

        // don't draw the org settings grid unless the user has permission
        // to view org settings in at least 1 org unit
        osContextSelector.store.fetch({query: {}, start: 0, count: 0, 
            onBegin: function(size) { 
                if(size) { osDraw();  return; }
                dojo.removeClass('no-perms', 'hide_me');
            }
        });
        
    };

    new openils.User().buildPermOrgSelector('VIEW_ORG_SETTINGS', osContextSelector, null, connect);

    fieldmapper.standardRequest(
        [   'open-ils.actor',
            'open-ils.actor.permissions.retrieve'],
        {   async: true,
            oncomplete: function(r) {
                var data = r.recv().content();
                if(e = openils.Event.parse(data))
                    return alert(e);
                for(var key in data)
                    perm_codes[data[key].id()] = data[key].code();
            }
        }
    );
    
    var aous = pcrud.retrieveAll('aou');
    dojo.forEach(aous, function(ou) { ouNames[ou.id()] = ou.shortname(); });
    
    showProcessingDialog(false);
}
dojo.addOnLoad(osInit);

function showProcessingDialog(toggle) {
    var proc = dojo.byId('proci18n').innerHTML;
    if(toggle)
        progressDialog.show(true, proc);
    else
        progressDialog.hide();
}

function osDraw(specific_setting) {
    showProcessingDialog(true);

    var names = [];
    if (specific_setting) {

        for(var key in specific_setting)
            names.push(key);

    } else {
        var types = new openils.PermaCrud({authtoken:authtoken}).retrieveAll('coust');

        searchAssist =  [];
        
        dojo.forEach(types, 
            function(type) {
                osSettings[type.name()] = {
                    label : type.label(),
                    desc : type.description(),
                    type : type.datatype(),
                    fm_class : type.fm_class(),
                    update_perm : type.update_perm(),
                    grp : osGroups[type.grp()]
                }
                
                var tmp = "" + type.label() + "" + type.description() + "" + type.fm_class() + "" + 
                          osGroups[type.grp()] + "" + type.name();
                
                searchAssist[type.name()] = tmp.toLowerCase().replace(/[^a-z0-9]+/g, '');
            }
        );
        
        for(var key in osSettings)
            names.push(key);
    }
    
    osDrawNames(names);
}

/**
 * Auto searches 500ms after entering text.
 */
var osCurrentSearchTimeout;
function osSearchChange() {
    if(osCurrentSearchTimeout != null)
        clearTimeout(osCurrentSearchTimeout);
        
    osCurrentSearchTimeout = setTimeout("doSearch()", 500);
}

//Limits those functions seen to the ones that have similar text to 
//that which is provided. Not case sensitive.
function osLimitSeen(text) {
    showProcessingDialog(true);
    
    text = text.split(' ');
    
    for(t in text)
        text[t] = text[t].toLowerCase().replace(/[^a-z0-9]+/g, '');
    
    numTerms = text.length;
    
    var names = [];
    for(var n in searchAssist) {
        var numFound = 0;
        
        for(var t in text) 
            if(searchAssist[n].indexOf(text[t]) != -1)
                numFound++;
                
        if(numFound == numTerms)
            names.push(n);
    }
    
    //Don't update on an empty list as this causes bizarre errors.
    if(names.length == 0) {
        showProcessingDialog(false);
        showAlert(dojo.byId('noresults').innerHTML);
        return;
    }
    
    ouSettingValues = {}; // Clear the values.
    osDrawNames(names); // Repopulate setting values with the ones we want.
}

function doSearch() {
    osCurrentSearchTimeout = null;
    
    var query = dojo.byId('searchBox').value;
    
    osLimitSeen(query);
    
    return false; //Keep form from submitting
}

function clearSearch() {
    if(dojo.byId('searchBox').value != '') { // Don't refresh on blank.
        dojo.byId('searchBox').value = '';
        doSearch();
    }
}

function osToJson() {
    var out = dojo.fromJson(dojo.toJson(ouSettingValues)); // Easy deep copy
    var context = osContextSelector.getValue();
    
    // Set all of the nulls in the outputs to be part of the current org
    // this keeps from overwriting later if this file is transfered to another lib.
    for(key in out)
        if(out[key] == null)
            out[key] = {'org':context, 'value':null};
    
    dojo.byId('jsonOutput').value = dojo.toJson(out);
    osJSONOutDialog.show();
}

// Copies the text from the json output to the clipboard.
function osJsonOutputCopy() {
    document.popupNode = dojo.byId('jsonOutput');
    dojo.byId('jsonOutput').focus();
    dojo.byId('jsonOutput').select();
    util.clipboard.copy();
    showAlert(dojo.byId('os-copy').innerHTML);
}

function osJsonInputPaste() {
    document.popupNode = dojo.byId('jsonInput');
    document.popupNode.focus();
    document.popupNode.select();
    util.clipboard.paste();
}

function osFromJson() {
     dojo.byId('jsonInput').value = '';
     osJSONInDialog.show();
}

function osFromJsonSubmit() {
    var input = dojo.byId('jsonInput').value;
    var from = dojo.fromJson(input);
    
    osJSONInDialog.hide();

    showProcessingDialog(true);
    for(key in from) {
        
        //Check that there isn't already set to the same value (speed increase);
        if( ouSettingValues[key] == null && 
            from[key]['value'] == null &&
            osContextSelector.getValue() == from[key]['org'])
            continue;
                
        if( ouSettingValues[key] != null && 
            ouSettingValues[key]['value'] == from[key]['value'] &&
            ouSettingValues[key]['org'] == from[key]['org'])
            continue;
        
        var obj = {};
        var context;
        
        if(from[key] != null) { 
            obj[key] = from[key]['value'];
            context  = from[key]['org'];
        }
        
        osUpdateSetting(obj, context);
    }
    showProcessingDialog(false);
}

//Draws the grid based upon a given array of items to draw.
function osDrawNames(names) {
    fieldmapper.standardRequest(
        [   'open-ils.actor', 
            'open-ils.actor.ou_setting.ancestor_default.batch'],
        {   async: true,
            params: [contextOrg, names, authtoken],
            oncomplete: function(r) {
                var data = r.recv().content();
                if(e = openils.Event.parse(data))
                    return alert(e);
                for(var key in data)
                    ouSettingValues[key] = data[key];
                osLoadGrid(ouSettingValues);
                
                showProcessingDialog(false);
            }
        }
    );
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
            if(seta.grp + "" + seta.label > setb.grp + "" + setb.label) return 1;
            if(seta.grp + "" + seta.label < setb.grp + "" + setb.label) return -1;
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
            if(setting.fm_class) {
                var autoWidget = new openils.widget.AutoFieldWidget(
                    {
                        fmClass : setting.fm_class,
                        selfReference : true,
                        widgetValue : value,
                        forceSync : true,
                        readOnly : true
                    }
                );
                autoWidget.build();
                if(autoWidget.getDisplayString())
                    return autoWidget.getDisplayString();
            }

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
    return this.value.replace(/SETTING/g, name);
}

function osLaunchEditor(name) {
    osEditDialog._osattr = name;
    osEditDialog.show();
    var perms = ['UPDATE_ORG_UNIT_SETTING_ALL'];
    if(osSettings[name].update_perm && perm_codes[osSettings[name].update_perm]) {
        perms.push(perm_codes[osSettings[name].update_perm]);
    }
    user.buildPermOrgSelector(
        perms,
        osEditContextSelector, osSettings[name].context
    );
    dojo.byId('os-edit-name').innerHTML = osSettings[name].label;
    dojo.byId('os-edit-desc').innerHTML = osSettings[name].desc || '';

    dojo.style(osEditTextBox.domNode, 'display', 'none');
    dojo.style(osEditCurrencyTextBox.domNode, 'display', 'none');
    dojo.style(osEditNumberTextBox.domNode, 'display', 'none');
    dojo.style(osEditBoolSelect.domNode, 'display', 'none');

    var fmClass = osSettings[name].fm_class;

    if(osEditAutoWidget) {
        osEditAutoWidget.domNode.parentNode.removeChild(osEditAutoWidget.domNode);
        osEditAutoWidget.destroy();
        osEditAutoWidget = null;
    }
    
    if(fmClass) {

        if(osEditAutoWidget) {
            osEditAutoWidget.domNode.parentNode.removeChild(osEditAutoWidget.domNode);
            osEditAutoWidget.destroy();
        }

        var autoWidget = new openils.widget.AutoFieldWidget(
            {
                fmClass : fmClass,
                selfReference : true,
                parentNode : dojo.create('div', null, dojo.byId('os-edit-auto-widget')),
                widgetValue : osSettings[name].value
            }
        );
        autoWidget.build(
            function(w) {
                osEditAutoWidget = w;
            }
        );

    } else {
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
}

function osEditSetting(deleteMe) {
    osEditDialog.hide();
    var name = osEditDialog._osattr;

    var obj = {};
    if(deleteMe) {
        obj[name] = null;
    } else {
        if(osSettings[name].fm_class) {
            var val = osEditAutoWidget.attr('value');
            osEditAutoWidget.domNode.parentNode.removeChild(osEditAutoWidget.domNode);
            osEditAutoWidget.destroy();
            osEditAutoWidget = null;
            if(val == null || val == '') return;
            obj[name] = val;

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
    }
    osUpdateSetting(obj, osEditContextSelector.getValue(), name);
}

function osUpdateSetting(obj, context, name) {
    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.org_unit.settings.update'],
        {   async: true,
            params: [authtoken, context, obj],
            oncomplete: function(r) {
                var res = r.recv().content();
                if(e = openils.Event.parse(res))
                    return alert(e);
                osDraw(obj);
                if(context != osContextSelector.getValue())
                    showAlert(dojo.byId('os-not-chosen').innerHTML);
            }
        }
    );
}

function osRevertSetting(context, name, value) {
    osHistDialog.hide();

    var obj = {};
    
    if(value == 'null' || value == null)
        obj[name] = null;
    else
        obj[name] = value;
    
    osUpdateSetting(obj, context, name);
}

function osGetHistoryLink(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    return data.name;
}

function osFormatHistoryLink(name) {
    return this.value.replace(/SETTING/, name);
}

function osLaunchHistory(name) {
    showProcessingDialog(true);
    
    dojo.byId('osHistName').innerHTML = osSettings[name].label;
    
    var data = dojo.byId('histTitle').innerHTML;
    var thisHist = pcrud.search('coustl', {'field_name':name});
    for(var i in thisHist.reverse()) {
        d = thisHist[i].date_applied();
        a = ouNames[thisHist[i].org()];
        o = thisHist[i].original_value();
        if(o) o=o.replace(/\&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        n = thisHist[i].new_value();
        if(n) n=n.replace(/\&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        r = thisHist[i].org();
        // Table is: Date | Org Name | Orig Value | New Value | Revert
        data += "<tr><td>" + d + "</td><td>" + a + "</td><td>" + o +
        "</td><td>" + n + "</td><td>" +
        "<a href='javascript:void(0);' onclick='osRevertSetting(" + r + ", &quot;" + name +"&quot;,"+o+");'>"+dojo.byId('os-revert').innerHTML+"</a></td></tr>";
    }
        
    dojo.byId('historyData').innerHTML = data;
    
    showProcessingDialog(false);
    osHistDialog.show();
}

function showAlert(message, timeout) {
    if(timeout == null) {
        timeout = 3000;
        if(message.length > 50)
            timeout = 5000;
        if(message.length > 80)
            timeout = 8000;
    }
    
    dojo.removeClass('msgCont', 'hidden');
    
    dojo.byId('msgInner').innerHTML = message;
    
    var fadeArgs = { node: "msgCont" };
    dojo.fadeIn(fadeArgs).play();
    
    window.setTimeout('hideAlert()', timeout);
    
}

function hideAlert() {
    var fadeArgs = { node: "msgCont" };
    dojo.fadeOut(fadeArgs).play();
    dojo.addClass('msgCont', 'hidden');
}

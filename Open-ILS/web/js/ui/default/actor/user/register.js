dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.ComboBox');
dojo.require('fieldmapper.IDL');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.Button');
dojo.require('dojo.date');
dojo.require('openils.CGI');
dojo.require('openils.XUL');

var pcrud;
var fmClasses = ['au', 'ac', 'aua', 'actsc', 'asv', 'asvq', 'asva'];
var fieldDoc = {};
var statCats;
var statCatTempate;
var surveys;
var staff;
var patron;
var uEditUsePhonePw = false;
var widgetPile = [];
var uEditCardVirtId = -1;
var uEditAddrVirtId = -1;
var orgSettings = {};
var tbody;
var addrTemplateRows;
var cgi;
var cloneUser;

if(!window.xulG) var xulG = null;


function load() {
    staff = new openils.User().user;
    pcrud = new openils.PermaCrud();
    cgi = new openils.CGI();
    cloneUser = cgi.param('clone');
    var userId = cgi.param('usr');

    if(xulG) {
	    if(xulG.ses) openils.User.authtoken = xulG.ses;
	    if(xulG.clone !== null) cloneUser = xulG.clone;
        if(xulG.usr !== null) userId = xulG.usr
        if(xulG.params) {
            var parms = xulG.params;
	        if(parms.ses) 
                openils.User.authtoken = parms.ses;
	        if(parms.clone) 
                cloneUser = parms.clone;
            if(parms.usr !== null)
                userId = parms.usr
        }
    }

    uEditLoadUser(userId);

    orgSettings = fieldmapper.aou.fetchOrgSettingBatch(staff.ws_ou(), [
        'global.juvenile_age_threshold',
        'patron.password.use_phone',
    ]);
    for(k in orgSettings)
        if(orgSettings[k])
            orgSettings[k] = orgSettings[k].value;

    var list = pcrud.search('fdoc', {fm_class:fmClasses});
    for(var i in list) {
        var doc = list[i];
        if(!fieldDoc[doc.fm_class()])
            fieldDoc[doc.fm_class()] = {};
        fieldDoc[doc.fm_class()][doc.field()] = doc;
    }

    tbody = dojo.byId('uedit-tbody');

    addrTemplateRows = dojo.query('tr[type=addr-template]', tbody);
    dojo.forEach(addrTemplateRows, function(row) { row.parentNode.removeChild(row); } );
    statCatTemplate = tbody.removeChild(dojo.byId('stat-cat-row-template'));
    surveyTemplate = tbody.removeChild(dojo.byId('survey-row-template'));
    surveyQuestionTemplate = tbody.removeChild(dojo.byId('survey-question-row-template'));

    loadStaticFields();
    if(patron.isnew()) 
        uEditNewAddr(null, uEditAddrVirtId);
    else loadAllAddrs();
    loadStatCats();
    loadSurveys();
}

function uEditLoadUser(userId) {
    if(!userId) return uEditNewPatron();
    patron = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.fleshed.retrieve'],
        {params : [openils.User.authtoken, userId]}
    );
}

function loadStaticFields() {
    for(var idx = 0; tbody.childNodes[idx]; idx++) {
        var row = tbody.childNodes[idx];
        if(row.nodeType != row.ELEMENT_NODE) continue;
        var fmcls = row.getAttribute('fmclass');
        if(!fmcls) continue;
        fleshFMRow(row, fmcls);
    }
}

function loadAllAddrs() {
    dojo.forEach(patron.addresses(),
        function(addr) {
            uEditNewAddr(null, addr.id());
        }
    );
}

function loadStatCats() {

    statCats = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.stat_cat.actor.retrieve.all'],
        {params : [openils.User.authtoken, staff.ws_ou()]}
    );

    // draw stat cats
    for(var idx in statCats) {
        var stat = statCats[idx];
        var row = statCatTemplate.cloneNode(true);
        row.id = 'stat-cat-row-' + idx;
        tbody.appendChild(row);
        getByName(row, 'name').innerHTML = stat.name();
        var valtd = getByName(row, 'widget');
        var span = valtd.appendChild(document.createElement('span'));
        var store = new dojo.data.ItemFileReadStore(
                {data:fieldmapper.actsc.toStoreData(stat.entries())});
        var comboBox = new dijit.form.ComboBox({store:store}, span);
        comboBox.labelAttr = 'value';
        comboBox.searchAttr = 'value';

        comboBox._wtype = 'statcat';
        comboBox._statcat = stat.id();
        widgetPile.push(comboBox); 

        // populate existing cats
        var map = patron.stat_cat_entries().filter(
            function(mp) { return (mp.stat_cat() == stat.id()) })[0];
        if(map) comboBox.attr('value', map.stat_cat_entry()); 

    }
}

function loadSurveys() {

    surveys = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.survey.retrieve.all'],
        {params : [openils.User.authtoken]}
    );

    // draw surveys
    for(var idx in surveys) {
        var survey = surveys[idx];
        var srow = surveyTemplate.cloneNode(true);
        tbody.appendChild(srow);
        getByName(srow, 'name').innerHTML = survey.name();

        for(var q in survey.questions()) {
            var quest = survey.questions()[q];
            var qrow = surveyQuestionTemplate.cloneNode(true);
            tbody.appendChild(qrow);
            getByName(qrow, 'question').innerHTML = quest.question();

            var span = getByName(qrow, 'answers').appendChild(document.createElement('span'));
            var store = new dojo.data.ItemFileReadStore(
                {data:fieldmapper.asva.toStoreData(quest.answers())});
            var select = new dijit.form.FilteringSelect({store:store}, span);
            select.labelAttr = 'answer';
            select.searchAttr = 'answer';

            select._wtype = 'survey';
            select._survey = survey.id();
            select._question = quest.id();
            widgetPile.push(select); 
        }
    }
}


function fleshFMRow(row, fmcls, args) {
    var fmfield = row.getAttribute('fmfield');
    var wclass = row.getAttribute('wclass');
    var wstyle = row.getAttribute('wstyle');
    var fieldIdl = fieldmapper.IDL.fmclasses[fmcls].field_map[fmfield];
    if(!args) args = {};

    var existing = dojo.query('td', row);
    var htd = existing[0] || row.appendChild(document.createElement('td'));
    var ltd = existing[1] || row.appendChild(document.createElement('td'));
    var wtd = existing[2] || row.appendChild(document.createElement('td'));

    openils.Util.addCSSClass(htd, 'uedit-help');
    if(fieldDoc[fmcls] && fieldDoc[fmcls][fmfield]) {
        var link = dojo.byId('uedit-help-template').cloneNode(true);
        link.id = '';
        link.onclick = function() { ueLoadContextHelp(fmcls, fmfield) };
        openils.Util.removeCSSClass(link, 'hidden');
        htd.appendChild(link);
    }

    if(!ltd.textContent) {
        var span = document.createElement('span');
        ltd.appendChild(document.createTextNode(fieldIdl.label));
    }

    span = document.createElement('span');
    wtd.appendChild(span);

    var fmObject = null;
    switch(fmcls) {
        case 'au' : fmObject = patron; break;
        case 'ac' : fmObject = patron.card(); break;
        case 'aua' : 
            fmObject = patron.addresses().filter(
                function(i) { return (i.id() == args.addr) })[0];
            break;
    }
    
    var widget = new openils.widget.AutoFieldWidget({
        idlField : fieldIdl,
        fmObject : fmObject,
        fmClass : fmcls,
        parentNode : span,
        widgetClass : wclass,
        dijitArgs : {style: wstyle},
        orgLimitPerms : ['UPDATE_USER'],
    });

    widget.build();
    widget._wtype = fmcls;
    widget._fmfield = fmfield;
    widget._addr = args.addr;
    widgetPile.push(widget);
    attachWidgetEvents(fmcls, fmfield, widget);
    return widget;
}

function findWidget(wtype, fmfield) {
    return widgetPile.filter(
        function(i){
            return (i._wtype == wtype && i._fmfield == fmfield);
        }
    ).pop();
}

function attachWidgetEvents(fmcls, fmfield, widget) {

    if(fmcls == 'ac') {
        if(fmfield == 'barcode') {
            dojo.connect(widget.widget, 'onChange',
                function() {
                    var un = findWidget('au', 'usrname');
                    if(!un.widget.attr('value'))
                        un.widget.attr('value', this.attr('value'));
                }
            );
        }
    }

    if(fmcls == 'au') {
        switch(fmfield) {

            case 'profile': // when the profile changes, update the expire date
                dojo.connect(widget.widget, 'onChange', 
                    function() {
                        var self = this;
                        var expireWidget = findWidget('au', 'expire_date');
                        function found(items) {
                            if(items.length == 0) return;
                            var item = items[0];
                            var interval = self.store.getValue(item, 'perm_interval');
                            expireWidget.widget.attr('value', dojo.date.add(new Date(), 
                                'second', openils.Util.intervalToSeconds(interval)));
                        }
                        this.store.fetch({onComplete:found, query:{id:this.attr('value')}});
                    }
                );
        }
    }
}

function getByName(node, name) {
    return dojo.query('[name='+name+']', node)[0];
}


function ueLoadContextHelp(fmcls, fmfield) {
    openils.Util.removeCSSClass(dojo.byId('uedit-help-div'), 'hidden');
    dojo.byId('uedit-help-field').innerHTML = fieldmapper.IDL.fmclasses[fmcls].field_map[fmfield].label;
    dojo.byId('uedit-help-text').innerHTML = fieldDoc[fmcls][fmfield].string();
}


/* creates a new patron object with card attached */
function uEditNewPatron() {
    patron = new au();
    patron.isnew(1);
    patron.id(-1);
    card = new ac();
    card.id(uEditCardVirtId);
    card.isnew(1);
    patron.card(card);
    patron.cards([card]);
    //patron.net_access_level(defaultNetLevel); XXX
    patron.stat_cat_entries([]);
    patron.survey_responses([]);
    patron.addresses([]);
    //patron.home_ou(USER.ws_ou()); XXX
    uEditMakeRandomPw(patron);
}

function uEditMakeRandomPw(patron) {
    if(uEditUsePhonePw) return;
    var rand  = Math.random();
    rand = parseInt(rand * 10000) + '';
    while(rand.length < 4) rand += '0';
/*
    appendClear($('ue_password_plain'),text(rand));
    unHideMe($('ue_password_gen'));
*/
    patron.passwd(rand);
    return rand;
}

function uEditWidgetVal(w) {
    var val = (w.getFormattedValue) ? w.getFormattedValue() : w.attr('value');
    if(val === '') val = null;
    return val;
}

function uEditSave() { _uEditSave(); }
function uEditSaveClone() { _uEditSave(true); }

function _uEditSave(doClone) {

    for(var idx in widgetPile) {
        var w = widgetPile[idx];
        var val = uEditWidgetVal(w);

        switch(w._wtype) {
            case 'au':
                patron[w._fmfield](val);
                break;

            case 'ac':
                patron.card()[w._fmfield](val);
                break;

            case 'aua':
                var addr = patron.addresses().filter(function(i){return (i.id() == w._addr)})[0];
                if(!addr) {
                    addr = new fieldmapper.aua();
                    addr.id(w._addr);
                    addr.isnew(1);
                    addr.usr(patron.id());
                    patron.addresses().push(addr);
                } else {
                    if(addr[w._fmfield]() != val)
                        addr.ischanged(1);
                }
                addr[w._fmfield](val);
                break;

            case 'survey':
                if(val == null) break;
                var resp = new fieldmapper.asvr();
                resp.isnew(1);
                resp.survey(w._survey)
                resp.usr(patron.id());
                resp.question(w._question)
                resp.answer(val);
                patron.survey_responses().push(resp);
                break;

            case 'statcat':
                if(val == null) break;

                var map = patron.stat_cat_entries().filter(
                    function(m){
                        return (m.stat_cat() == w._statcat) })[0];

                if(map) {
                    if(map.stat_cat_entry() == val) 
                        break;
                    map.ischanged(1);
                } else {
                    map = new fieldmapper.actscecm();
                    map.isnew(1);
                }

                map.stat_cat(w._statcat);
                map.stat_cat_entry(val);
                map.target_usr(patron.id());
                patron.stat_cat_entries().push(map);
                break;
        }
    }

    patron.ischanged(1);
    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.patron.update'],
        {   async: true,
            params: [openils.User.authtoken, patron],
            oncomplete: function(r) {
                newPatron = openils.Util.readResponse(r);
                if(newPatron) uEditFinishSave(newPatron, doClone);
            }
        }
    );
}

function uEditFinishSave(newPatron, doClone) {

    if(doClone &&cloneUser == null)
        cloneUser = newPatron.id();

	if( doClone ) {

		if(xulG && typeof xulG.spawn_editor == 'function' && !patron.isnew() ) {
            window.xulG.spawn_editor({ses:openils.User.authtoken,clone:cloneUser});
            uEditRefresh();

		} else {
			location.href = href.replace(/\?.*/, '') + '?clone=' + cloneUser;
		}

	} else {

		uEditRefresh();
	}

	uEditRefreshXUL(newPatron);
}

function uEditRefresh() {
    var usr = cgi.param('usr');
    var href = location.href.replace(/\?.*/, '');
    href += ((usr) ? '?usr=' + usr : '');
    location.href = href;
}

function uEditRefreshXUL(newuser) {
	if (window.xulG && typeof window.xulG.on_save == 'function') 
		window.xulG.on_save(newuser);
}


function uEditNewAddr(evt, id) {
    if(id == null) id = --uEditAddrVirtId;
    dojo.forEach(addrTemplateRows, 
        function(row) {
            row = tbody.insertBefore(row.cloneNode(true), dojo.byId('new-addr-row'));
            row.setAttribute('type', '');
            row.setAttribute('addr', id+'');
            if(row.getAttribute('fmclass')) {
                fleshFMRow(row, 'aua', {addr:id});
            } else {
               var btn = dojo.query('[name=delete-button]', row)[0];
               if(btn) btn.onclick = function(){ uEditDeleteAddr(id) };
            }
        }
    );
}


function uEditDeleteAddr(id) {
    if(!confirm('Delete address ' + id)) return; /* XXX i18n */
    var rows = dojo.query('tr[addr='+id+']', tbody);
    for(var i = 0; i < rows.length; i++)
        rows[i].parentNode.removeChild(rows[i]);
    widgetPile = widgetPile.filter(function(w){return (w._addr != id)});
}

function uEditToggleRequired() {
    if((tbody.className +'').match(/hide-non-required/))
        openils.Util.removeCSSClass(tbody, 'hide-non-required');
    else
        openils.Util.addCSSClass(tbody, 'hide-non-required');
}



openils.Util.addOnLoad(load);

dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.FilteringSelect');
dojo.require('fieldmapper.IDL');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('dijit.form.CheckBox');

var pcrud;
var fmClasses = ['au', 'ac', 'aua', 'actsc', 'asv', 'asvq', 'asva'];
var fieldDoc = {};


function load() {
    pcrud = new openils.PermaCrud();
    pcrud.search('fdoc', 
        {fm_class:fmClasses},
        {
            oncomplete : function(r) {
                var list = openils.Util.readResponse(r, null, true);
                for(var i in list) {
                    var doc = list[i];
                    if(!fieldDoc[doc.fm_class()])
                        fieldDoc[doc.fm_class()] = {};
                    fieldDoc[doc.fm_class()][doc.field()] = doc;
                }
                loadTable();
            }
        }
    );
}

function loadTable() {
    var tbody = dojo.byId('uedit-tbody');

    for(var idx = 0; tbody.childNodes[idx]; idx++) {

        var row = tbody.childNodes[idx];
        if(row.nodeType != row.ELEMENT_NODE) continue;
        var fmcls = row.getAttribute('fmclass');
        if(!fmcls) continue;

        var fmfield = row.getAttribute('fmfield');
        var wclass = row.getAttribute('wclass');
        var wstyle = row.getAttribute('wstyle');
        var fieldIdl = fieldmapper.IDL.fmclasses[fmcls].field_map[fmfield];

        if(!fieldIdl)
            console.log("failed loading " + fmcls + ' : ' + fmfield);

        var existing = dojo.query('td', row);
        var htd = existing[0] || row.appendChild(document.createElement('td'));
        var ltd = existing[1] || row.appendChild(document.createElement('td'));
        var wtd = existing[2] || row.appendChild(document.createElement('td'));

        openils.Util.addCSSClass(htd, 'uedit-help');
        if(fieldDoc[fmcls] && fieldDoc[fmcls][fmfield]) {
            var link = dojo.byId('uedit-help-template').cloneNode(true);
            link.id = '';
            link.setAttribute('href', 'javascript:ueLoadContextHelp("'+fmcls+'","'+fmfield+'")');
            openils.Util.removeCSSClass(link, 'hidden');
            htd.appendChild(link);
            console.log(link.href);
        }

        if(!ltd.textContent) {
            var span = document.createElement('span');
            ltd.appendChild(document.createTextNode(fieldIdl.label));
        }

        span = document.createElement('span');
        wtd.appendChild(span);

        var widget = new openils.widget.AutoFieldWidget({
            idlField : fieldIdl,
            fmObject : null, // XXX
            fmClass : fmcls,
            parentNode : span,
            widgetClass : wclass,
            dijitArgs : {style: wstyle},
            orgLimitPerms : ['UPDATE_USER'],
        });
        widget.build();
    }
}

function ueLoadContextHelp(fmcls, fmfield) {
    openils.Util.removeCSSClass(dojo.byId('uedit-help-div'), 'hidden');
    dojo.byId('uedit-help-field').innerHTML = fieldmapper.IDL.fmclasses[fmcls].field_map[fmfield].label;
    dojo.byId('uedit-help-text').innerHTML = fieldDoc[fmcls][fmfield].string();
}


openils.Util.addOnLoad(load);


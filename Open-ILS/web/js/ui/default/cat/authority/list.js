dojo.require('dijit.form.Button');
dojo.require('dijit.form.DropDownButton');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.NumberSpinner');
dojo.require('dijit.form.TextBox');
dojo.require("dijit.Menu");
dojo.require("dijit.MenuItem");
dojo.require('dojox.xml.parser');
dojo.require('openils.CGI');
dojo.require('dojo.dnd.Source');
dojo.require('openils.PermaCrud');
dojo.require('openils.XUL');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var cgi = new openils.CGI();

/*
// OrgUnits do not currently affect the retrieval of authority records,
// but this is how to display them if they become OrgUnit-aware
function authOUListInit() {
    new openils.User().buildPermOrgSelector(
        "STAFF_LOGIN", // anywhere you can log in
        dijit.byId("authOU"),
        null, // pre-selected org
        null
    );
}
dojo.addOnLoad(authOUListInit);
*/
function displayAuthorities(data) { 
    // Grab each record from the returned authority records
    dojo.query("record", data).forEach(function(node) {
        authText = '';
        authId = 0;

        // Grab each authority record field from the authority record
        dojo.query("datafield[tag^='1']", node).forEach(function(dfNode) {
            authText += dojox.xml.parser.textContent(dfNode); 
        });
        // Grab the ID of the authority record
        dojo.query("datafield[tag='901'] subfield[code='c']", node).forEach(function(dfNode) {
            authId = dojox.xml.parser.textContent(dfNode); 
        });

        // Create the authority record listing entry
        dojo.place('<div class="authEntry" id="auth' + authId + '"><span class="text">' + authText + '</span></div>', "authlist-div", "last");

        // Add the menu of new/edit/delete/mark-for-merge options
        var auth_menu = new dijit.Menu({});

        // "Edit" menu item
        new dijit.MenuItem({"id": "edit_" + authId, "onClick": function(){
            recId = this.id.slice(this.id.lastIndexOf('_') + 1);
            pcrud = new openils.PermaCrud();
            auth_rec = pcrud.retrieve("are", recId);
            if (auth_rec) {
                loadMarcEditor(pcrud, auth_rec);
            }
        }, "label":"Edit"}).placeAt(auth_menu, "first");

        // "Merge" menu item
        new dijit.MenuItem({"id": "merge_" + authId, "onClick":function(){
            authText = '';
            recId = this.id.slice(this.id.lastIndexOf('_') + 1);
            dojo.query('#auth' + recId + ' span.text').forEach(function(node) {
                authText += dojox.xml.parser.textContent(node); 
            });
            dojo.place('<div class="toMerge" id="toMerge_' + recId + '">' +  authText + '</div>', 'mergebox-div', 'last');
            dojo.removeClass('mergebox-div', 'hidden');
        }, "label":"Mark for Merge"}).placeAt(auth_menu, "last");

        // "Delete" menu item
        new dijit.MenuItem({"id": "delete_" + authId, "onClick":function(){
            recId = this.id.slice(this.id.lastIndexOf('_') + 1);

            // Deleting an authority record is unusual; let's be 100% sure
            if (!confirm("Are you sure you want to delete record " + recId + "?")) {
                return;
            }

            pcrud = new openils.PermaCrud();
            auth_rec = pcrud.retrieve("are", recId);
            if (auth_rec) {
                pcrud.eliminate(auth_rec);
                alert("Deleted authority record # " + recId);
            }
        }, "label":"Delete"}).placeAt(auth_menu, "last");

        auth_mb = new dijit.form.DropDownButton({dropDown: auth_menu, label:"Actions"});
        auth_mb.placeAt("auth" + authId, "first");
        auth_menu.startup();
    });
}

function loadMarcEditor(pcrud, rec) {
    /*
       To run in Firefox directly, must set signed.applets.codebase_principal_support
       to true in about:config
     */
    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
    win = window.open('/xul/server/cat/marcedit.xul'); // XXX version?

    win.xulG = {
        "record": {"marc": rec.marc()},
        "save": {
            "label": "Save",
            "func": function(xmlString) {
                rec.marc(xmlString);
                rec.ischanged(true);
                pcrud.update(rec);
                alert("Record was saved");
                win.close();
            }
        }
    };
}

function authListInit() {
    term = cgi.param('authTerm') || '';
    page = cgi.param('authPage') || 0;
    axis = cgi.param('authAxis') || 'authority.author';
    if (axis) {
        dijit.byId('authAxis').attr('value', axis);
    }
    if (page) {
        dijit.byId('authPage').attr('value', page);
    }
    if (term) {
        dijit.byId('authTerm').attr('value', term);
        displayRecords();
    }
    dojo.connect(dijit.byId('authTerm'), 'onBlur', 'displayRecords');
}
dojo.addOnLoad(authListInit);

function displayRecords(parms) {

    if (parms && parms.page) {
        if (parms.page == 'next') {
            page = dijit.byId('authPage').attr('value');
            dijit.byId('authPage').attr('value', page + 1);
        } else if (parms.page == 'prev') {
            page = dijit.byId('authPage').attr('value');
            dijit.byId('authPage').attr('value', page - 1);
        } else {
            dijit.byId('authPage').attr('value', parms.page);
        }
    }

    /* Protect against null input */
    if (!dijit.byId('authTerm').attr('value')) {
        return;
    }

    /* Clear out the current contents of the page */
    widgets = dijit.findWidgets(dojo.byId('authlist-div'));
    dojo.forEach(widgets, function(w) { w.destroyRecursive(true); });

    dojo.query("#authlist-div div").orphan();

    url = '/opac/extras/startwith/marcxml/'
        + dijit.byId('authAxis').attr('value')
        // + '/' + dijit.byId('authOU').attr('value')
        + '/1' // replace with preceding line if OUs gain some meaning
        + '/' + dijit.byId('authTerm').attr('value')
        + '/' + dijit.byId('authPage').attr('value')
    ;
    dojo.xhrGet({"url":url, "handleAs":"xml", "content":{"format":"marcxml"}, "preventCache": true, "load":displayAuthorities });
}

function clearMergeRecords() {
    records = dojo.query('.toMerge').orphan();
    dojo.addClass('mergebox-div', 'hidden');
}

function mergeRecords() {
    records = dojo.query('.toMerge').attr('id');
    dojo.forEach(records, function(item, idx) {
        records[idx] = parseInt(item.slice(item.lastIndexOf('_') + 1));
    });
    alert('TODO: actually merge the gathered records: ' + dojo.toJson(records));
}

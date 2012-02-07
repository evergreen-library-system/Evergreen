dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var linkedEditor = null;
var circModEntryCache = [];
var limitGroupEntryCache = [];
var circModCache = {};
var limitGroupCache = {};
var curLinkedEditor;

function load(){
    clsGrid.loadAll({order_by:{ccls:'name'}});
    clsGrid.onEditPane = buildEditPaneAdditions;
    clsGrid.onPostUpdate = updateLinked;
    clsGrid.onPostCreate = updateLinked;
    linkedEditor = dojo.byId('linked-editor').parentNode.removeChild(dojo.byId('linked-editor'));

    // Cache circ mod/limit group info for later display
    var pcrud = new openils.PermaCrud();
    var temp = pcrud.retrieveAll('ccm');
    dojo.forEach(temp, function(g) { circModCache[g.code()] = g; } );
    temp = pcrud.retrieveAll('cclg');
    dojo.forEach(temp, function(g) { limitGroupCache[g.id()] = g; } );
}

function byName(name, ctxt) {
    return dojo.query('[name=' + name + ']', ctxt)[0];
}

function buildEditPaneAdditions(editPane) {
    circModEntryCache = [];
    limitGroupEntryCache = [];
    var tr = document.createElement('tr');
    var td = document.createElement('td');
    td.setAttribute('colspan','2');
    // Explanation....
    // editPane.domNode.lastChild = Table
    // .lastChild = Table Body
    // .lastChild = Table Row containing Action Buttons
    editPane.domNode.lastChild.lastChild.insertBefore(tr, editPane.domNode.lastChild.lastChild.lastChild);
    tr.appendChild(td);
    curLinkedEditor = linkedEditor.cloneNode(true);
    td.appendChild(curLinkedEditor);
    var circModTmpl = byName('circ-mod-entry-tbody', curLinkedEditor).removeChild(byName('circ-mod-entry-row', curLinkedEditor));
    var limitGroupTmpl = byName('limit-group-entry-tbody', curLinkedEditor).removeChild(byName('limit-group-entry-row', curLinkedEditor));

    var cm_selector = new openils.widget.AutoFieldWidget({
        fmClass : 'cclscmm',
        fmField : 'circ_mod',
        parentNode : byName('circ-mod-selector', curLinkedEditor)
    });
    cm_selector.build();

    var lg_selector = new openils.widget.AutoFieldWidget({
        fmClass : 'cclsgm',
        fmField : 'limit_group',
        parentNode : byName('limit-group-selector', curLinkedEditor)
    });
    lg_selector.build();

    function addMod(code) {
        var row = circModTmpl.cloneNode(true);
        row.setAttribute('code', code);
        byName('circ-mod', row).innerHTML = code + ' : ' + circModCache[code].name();
        byName('remove-circ-mod', row).onclick = function() {
            byName('circ-mod-entry-tbody', clsGrid.editPane.domNode).removeChild(row);
        }
        byName('circ-mod-entry-tbody', editPane.domNode).appendChild(row);
    }

    function addGroup(group) {
        var row = limitGroupTmpl.cloneNode(true);
        row.setAttribute('limit_group', group);
        byName('limit-group', row).innerHTML = limitGroupCache[group].name();
        byName('remove-limit-group', row).onclick = function() {
            byName('limit-group-entry-tbody', clsGrid.editPane.domNode).removeChild(row);
        }
        byName('limit-group-entry-tbody', editPane.domNode).appendChild(row);
    }

    byName('add-circ-mod', editPane.domNode).onclick = function() {
        addMod(cm_selector.widget.attr('value'));
    }

    byName('add-limit-group', editPane.domNode).onclick = function() {
        addGroup(lg_selector.widget.attr('value'));
    }

    // On edit we need to load existing entries.
    // On create, not so much.
    if(!editPane.fmObject) return; 
    var limitSet = editPane.fmObject.id();

    if(editPane.mode == 'update') {
        var pcrud = new openils.PermaCrud();
        circModEntryCache = pcrud.search('cclscmm', {limit_set: limitSet});
        limitGroupEntryCache = pcrud.search('cclsgm', {limit_set: limitSet});
        dojo.forEach(circModEntryCache, function(g) { addCircMod(circModTmpl, g); } );
        dojo.forEach(limitGroupEntryCache, function(g) { addLimitGroup(limitGroupTmpl, g); } );
    } 
}

function addCircMod(tmpl, circ_mod_entry) {
    var row = tmpl.cloneNode(true);
    var code = circ_mod_entry.circ_mod();
    row.setAttribute('code', code);
    byName('circ-mod', row).innerHTML = code + ' : ' + circModCache[code].name();
    byName('remove-circ-mod', row).onclick = function() {
        byName('circ-mod-entry-tbody', clsGrid.editPane.domNode).removeChild(row);
    }
    byName('circ-mod-entry-tbody', clsGrid.editPane.domNode).appendChild(row);
}

function addLimitGroup(tmpl, limit_group_entry) {
    var row = tmpl.cloneNode(true);
    var group = limit_group_entry.limit_group();
    row.setAttribute('limit_group', group);
    byName('limit-group', row).innerHTML = limitGroupCache[group].name();
    if(limit_group_entry.check_only() == 't') {
        byName('limit-group-check-only', row).setAttribute('checked', 'true');
    }
    byName('remove-limit-group', row).onclick = function() {
        byName('limit-group-entry-tbody', clsGrid.editPane.domNode).removeChild(row);
    }
    byName('limit-group-entry-tbody', clsGrid.editPane.domNode).appendChild(row);
}

function updateLinked(fmObject, rowindex) {
    var id = null;
    if(rowindex != undefined && this.editPane && this.editPane.fmObject) {
        // Edit, grab existing ID
        id = this.editPane.fmObject.id();
    } else if(fmObject.id) {
        // Create, grab new ID
        id = fmObject.id();
    }
    // If we don't have an ID, drop out.
    if(id == null) return;
    var pcrud = new openils.PermaCrud();
    progressDialog.show(true);

    var add = [];
    var remove = [];
    var update = [];

    // First up, circ mods.
    var circ_mods = [];
    dojo.query('[name=circ-mod-entry-row]', this.editPane.domNode).forEach(
        function(row) {
            var mod = row.getAttribute('code');
            circ_mods.push(mod);
            if(!circModEntryCache.filter(function(i) { return (i.circ_mod() == mod); })[0]) {
                var entry = new fieldmapper.cclscmm();
                entry.isnew(true);
                entry.limit_set(id);
                entry.circ_mod(mod);
                add.push(entry);
            }
        }
    );
    dojo.forEach(circModEntryCache, function(eMod) {
            if(!circ_mods.filter(function(i) { return (i == eMod.circ_mod()); })[0]) {
                eMod.isdeleted(true);
                remove.push(eMod);
            }
        }
    );

    // Next, limit groups
    var limit_groups = [];
    dojo.query('[name=limit-group-entry-row]', this.editPane.domNode).forEach(
        function(row) {
            var group = row.getAttribute('limit_group');
            limit_groups.push(group);
            var cached = limitGroupEntryCache.filter(function(i) { return (i.limit_group() == group); })[0];
            if(!cached) {
                var entry = new fieldmapper.cclsgm();
                entry.isnew(true);
                entry.limit_set(id);
                entry.limit_group(group);
                entry.check_only(byName('limit-group-check-only', row).checked ? 't' : 'f');
                add.push(entry);
            } else {
                var check_only = byName('limit-group-check-only', row).checked;
                if(check_only != (cached.check_only() == 't')) {
                    cached.check_only(check_only ? 't' : 'f');
                    cached.ischanged(true);
                    update.push(cached);
                }
            }
        }
    );
    dojo.forEach(limitGroupEntryCache, function(eGroup) {
            if(!limit_groups.filter(function(i) { return (i == eGroup.limit_group()); })[0]) {
                eGroup.isdeleted(true);
                remove.push(eGroup);
            }
        }
    );

    function updateEntries() {
        pcrud.update(update, {
            oncomplete : function () {
                progressDialog.hide();
            }
        });
    }

    function removeEntries() {
        pcrud.eliminate(remove, {
            oncomplete : function () {
                if(update.length) {
                    updateEntries();
                } else {
                    progressDialog.hide();
                }
            }
        });
    }

    function addEntries() {
        pcrud.create(add, {
            oncomplete : function () {
                if(remove.length) {
                    removeEntries();
                } else if (update.length) {
                    updateEntries();
                } else {
                    progressDialog.hide();
                }
            }
        });
    }

    if(add.length)
        addEntries();
    else if (remove.length)
        removeEntries();
    else if (update.length)
        updateEntries();
    else
        progressDialog.hide();
}

openils.Util.addOnLoad(load);


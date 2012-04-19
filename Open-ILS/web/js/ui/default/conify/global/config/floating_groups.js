dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var groupMemberEditor = null;
var groupMemberEntryCache = [];
var orgUnitCache = {};

function load(){
    cfgGrid.loadAll({order_by:{cfg:'name'}});
    cfgGrid.onEditPane = buildEditPaneAdditions;
    cfgGrid.onPostUpdate = updateLinked;
    cfgGrid.onPostCreate = updateLinked;
    groupMemberEditor = dojo.byId('group-member-editor').parentNode.removeChild(dojo.byId('group-member-editor'));

    // Cache org unit info for later display
    var pcrud = new openils.PermaCrud();
    var temp = pcrud.retrieveAll('aou');
    dojo.forEach(temp, function(g) { orgUnitCache[g.id()] = g; } );
}

function byName(name, ctxt) {
    return dojo.query('[name=' + name + ']', ctxt)[0];
}

function buildEditPaneAdditions(editPane) {
    groupMemberEntryCache = [];
    var tr = document.createElement('tr');
    var td = document.createElement('td');
    td.setAttribute('colspan','2');
    // Explanation....
    // editPane.domNode.lastChild = Table
    // .lastChild = Table Body
    // .lastChild = Table Row containing Action Buttons
    editPane.domNode.lastChild.lastChild.insertBefore(tr, editPane.domNode.lastChild.lastChild.lastChild);
    tr.appendChild(td);
    curGroupMemberEditor = groupMemberEditor.cloneNode(true);
    td.appendChild(curGroupMemberEditor);
    var groupMemberTmpl = byName('group-member-entry-tbody', curGroupMemberEditor).removeChild(byName('group-member-entry-row', curGroupMemberEditor));

    var selector = new openils.widget.AutoFieldWidget({
        fmClass : 'cfgm',
        fmField : 'org_unit',
        parentNode : byName('org-unit-selector', curGroupMemberEditor)
    });
    selector.build();

    function addMember(ounit) {
        var row = groupMemberTmpl.cloneNode(true);
        row.setAttribute('org_unit', ounit);
        byName('org-unit', row).innerHTML = orgUnitCache[ounit].shortname();
        byName('remove-group-member', row).onclick = function() {
            byName('group-member-entry-tbody', cfgGrid.editPane.domNode).removeChild(row);
        }
        byName('group-member-entry-tbody', editPane.domNode).appendChild(row);
    }

    byName('add-group-member', editPane.domNode).onclick = function() {
        addMember(selector.widget.attr('value'));
    }

    // On edit we need to load existing entries.
    // On create, not so much.
    if(!editPane.fmObject) return; 

    if(editPane.mode == 'update') {
        var pcrud = new openils.PermaCrud();
        groupMemberEntryCache = pcrud.search('cfgm', {floating_group: editPane.fmObject.id()});
        dojo.forEach(groupMemberEntryCache, function(g) { addGroupMember(groupMemberTmpl, g); } );
    } 
}

function addGroupMember(tmpl, group_member_entry) {
    var row = tmpl.cloneNode(true);
    row.setAttribute('group_member', group_member_entry.id());
    byName('org-unit', row).innerHTML = orgUnitCache[group_member_entry.org_unit()].shortname();
    byName('group-member-stop-depth', row).value = group_member_entry.stop_depth();
    if(group_member_entry.max_depth() != null) {
        byName('group-member-max-depth', row).value = group_member_entry.max_depth();
    }
    if(group_member_entry.exclude() == 't') {
        byName('group-member-exclude', row).setAttribute('checked', 'true');
    }
    byName('remove-group-member', row).onclick = function() {
        byName('group-member-entry-tbody', cfgGrid.editPane.domNode).removeChild(row);
    }
    byName('group-member-entry-tbody', cfgGrid.editPane.domNode).appendChild(row);
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

    var group_members = [];
    dojo.query('[name=group-member-entry-row]', this.editPane.domNode).forEach(
        function(row) {
            var member_id = row.getAttribute('group_member');
            var cached;
            if (member_id)
                cached = groupMemberEntryCache.filter(function(i) { return (i.id() == member_id); })[0];
            var stop_depth = byName('group-member-stop-depth', row).value;
            var max_depth = byName('group-member-max-depth', row).value;
            if (max_depth === '') max_depth = null;
            var exclude = byName('group-member-exclude', row).checked;
            if (cached) {
                group_members.push(member_id);
                if((stop_depth != cached.stop_depth()) || (max_depth !== cached.max_depth()) || (exclude != (cached.exclude() == 't'))) {
                    cached.stop_depth(stop_depth);
                    cached.max_depth(max_depth);
                    cached.exclude(exclude ? 't' : 'f');
                    cached.ischanged(true);
                    update.push(cached);
                }
            } else {
                var entry = new fieldmapper.cfgm();
                var org_unit = row.getAttribute('org_unit');
                entry.isnew(true);
                entry.floating_group(id);
                entry.org_unit(org_unit);
                entry.stop_depth(stop_depth);
                entry.max_depth(max_depth);
                entry.exclude(exclude ? 't' : 'f');
                add.push(entry);
            }
        }
    );
    dojo.forEach(groupMemberEntryCache, function(eMember) {
            if(!group_members.filter(function(i) { return (i == eMember.id()); })[0]) {
                eMember.isdeleted(true);
                remove.push(eMember);
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


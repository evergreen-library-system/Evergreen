dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var limitSetEditor = null;
var limitSetEntryCache = [];
var limitSetCache = {};

function load(){
    cmGrid.overrideWidgetArgs.grp = {hrbefore : true};
    cmGrid.overrideWidgetArgs.is_renewal = {ternary : true};
    cmGrid.overrideWidgetArgs.ref_flag = {ternary : true};
    cmGrid.overrideWidgetArgs.juvenile_flag = {ternary : true};
    cmGrid.overrideWidgetArgs.circulate = {inherits : true, hrbefore : true};
    cmGrid.overrideWidgetArgs.duration_rule = {inherits : true};
    cmGrid.overrideWidgetArgs.recurring_fine_rule = {inherits : true};
    cmGrid.overrideWidgetArgs.max_fine_rule = {inherits : true};
    cmGrid.overrideWidgetArgs.available_copy_hold_ratio = {inherits : true};
    cmGrid.overrideWidgetArgs.total_copy_hold_ratio = {inherits : true};
    cmGrid.overrideWidgetArgs.renewals = {inherits : true};
    cmGrid.overrideWidgetArgs.grace_period = {inherits : true};
    cmGrid.overrideWidgetArgs.hard_due_date = {inherits : true};
    cmGrid.loadAll({order_by:{ccmm:'circ_modifier'}});
    cmGrid.onEditPane = buildEditPaneAdditions;
    cmGrid.onPostUpdate = updateLinked;
    cmGrid.onPostCreate = updateLinked;
    limitSetEditor = dojo.byId('limit-set-editor').parentNode.removeChild(dojo.byId('limit-set-editor'));

    // Cache limit set info for later display
    var pcrud = new openils.PermaCrud();
    var temp = pcrud.retrieveAll('ccls');
    dojo.forEach(temp, function(g) { limitSetCache[g.id()] = g; } );
}

function byName(name, ctxt) {
    return dojo.query('[name=' + name + ']', ctxt)[0];
}

function buildEditPaneAdditions(editPane) {
    limitSetEntryCache = [];
    var tr = document.createElement('tr');
    var td = document.createElement('td');
    td.setAttribute('colspan','2');
    // Explanation....
    // editPane.domNode.lastChild = Table
    // .lastChild = Table Body
    // .lastChild = Table Row containing Action Buttons
    editPane.domNode.lastChild.lastChild.insertBefore(tr, editPane.domNode.lastChild.lastChild.lastChild);
    tr.appendChild(td);
    curLimitSetEditor = limitSetEditor.cloneNode(true);
    td.appendChild(curLimitSetEditor);
    var limitSetTmpl = byName('limit-set-entry-tbody', curLimitSetEditor).removeChild(byName('limit-set-entry-row', curLimitSetEditor));

    var selector = new openils.widget.AutoFieldWidget({
        fmClass : 'ccmlsm',
        fmField : 'limit_set',
        parentNode : byName('limit-set-selector', curLimitSetEditor)
    });
    selector.build();

    function addSet(lset) {
        var row = limitSetTmpl.cloneNode(true);
        row.setAttribute('limit_set', lset);
        byName('limit-set', row).innerHTML = limitSetCache[lset].name();
        byName('remove-limit-set', row).onclick = function() {
            byName('limit-set-entry-tbody', cmGrid.editPane.domNode).removeChild(row);
        }
        byName('limit-set-active', row).setAttribute('checked', 'true');
        byName('limit-set-entry-tbody', editPane.domNode).appendChild(row);
    }

    byName('add-limit-set', editPane.domNode).onclick = function() {
        addSet(selector.widget.attr('value'));
    }

    // On edit we need to load existing entries.
    // On create, not so much.
    if(!editPane.fmObject) return; 
    var matchpoint = editPane.fmObject.id();

    if(editPane.mode == 'update') {
        var pcrud = new openils.PermaCrud();
        limitSetEntryCache = pcrud.search('ccmlsm', {matchpoint: editPane.fmObject.id()});
        dojo.forEach(limitSetEntryCache, function(g) { addLimitSet(limitSetTmpl, g); } );
    } 
}

function addLimitSet(tmpl, limit_set_entry) {
    var row = tmpl.cloneNode(true);
    var lset = limit_set_entry.limit_set();
    row.setAttribute('limit_set', lset);
    byName('limit-set', row).innerHTML = limitSetCache[lset].name();
    if(limit_set_entry.active() == 't') {
        byName('limit-set-active', row).setAttribute('checked', 'true');
    }
    if(limit_set_entry.fallthrough() == 't') {
        byName('limit-set-fallthrough', row).setAttribute('checked', 'true');
    }
    byName('remove-limit-set', row).onclick = function() {
        byName('limit-set-entry-tbody', cmGrid.editPane.domNode).removeChild(row);
    }
    byName('limit-set-entry-tbody', cmGrid.editPane.domNode).appendChild(row);
}

function format_hard_due_date(name, id) {
    var item=this.grid.getItem(id);
    if(!item) return name;
    switch (this.grid.store.getValue(this.grid.getItem(id), 'hard_due_date')) {
        case null :
        case undefined :
        case 'unset' :
            return name;
        default:
            return "<a href='" + oilsBasePath +
                "/conify/global/config/hard_due_date?name=" +
                encodeURIComponent(name) + "'>" + name + "</a>";
    }
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

    var limit_sets = [];
    dojo.query('[name=limit-set-entry-row]', this.editPane.domNode).forEach(
        function(row) {
            var lset = row.getAttribute('limit_set');
            limit_sets.push(lset);
            var cached = limitSetEntryCache.filter(function(i) { return (i.limit_set() == lset); })[0];
            if(!cached) {
                var entry = new fieldmapper.ccmlsm();
                entry.isnew(true);
                entry.matchpoint(id);
                entry.limit_set(lset);
                entry.active(byName('limit-set-active', row).checked ? 't' : 'f');
                entry.fallthrough(byName('limit-set-fallthrough', row).checked ? 't' : 'f');
                add.push(entry);
            } else {
                var active = byName('limit-set-active', row).checked;
                var fallthrough = byName('limit-set-fallthrough', row).checked;
                if((active != (cached.active() == 't')) || (fallthrough != (cached.fallthrough() == 't'))) {
                    cached.active(active ? 't' : 'f');
                    cached.fallthrough(fallthrough ? 't' : 'f');
                    cached.ischanged(true);
                    update.push(cached);
                }
            }
        }
    );
    dojo.forEach(limitSetEntryCache, function(eSet) {
            if(!limit_sets.filter(function(i) { return (i == eSet.limit_set()); })[0]) {
                eSet.isdeleted(true);
                remove.push(eSet);
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


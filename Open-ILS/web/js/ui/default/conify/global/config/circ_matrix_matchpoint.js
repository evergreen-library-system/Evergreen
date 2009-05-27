dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var circModEditor = null;
var circModGroupTables = [];
var circModGroupCache = {};
var circModEntryCache = {};
var matchPoint;

function load(){
    cmGrid.loadAll({order_by:{ccmm:'circ_modifier'}});
    cmGrid.onEditPane = buildEditPaneAdditions;
    circModEditor = dojo.byId('circ-mod-editor').parentNode.removeChild(dojo.byId('circ-mod-editor'));
}

function byName(name, ctxt) {
    return dojo.query('[name=' + name + ']', ctxt)[0];
}

function buildEditPaneAdditions(editPane) {
    var node = circModEditor.cloneNode(true);
    var tableTmpl = node.removeChild(byName('circ-mod-group-table', node));
    circModGroupTables = [];
    matchPoint = editPane.fmObject.id();

    byName('add-circ-mod-group', node).onclick = function() {
        addCircModGroup(node, tableTmpl)
    }

    if(editPane.mode == 'update') {
        var groups = new openils.PermaCrud().search('ccmcmt', {matchpoint: editPane.fmObject.id()});
        dojo.forEach(groups, function(g) { addCircModGroup(node, tableTmpl, g); } );
    } 

    editPane.domNode.appendChild(node);
}


function addCircModGroup(node, tableTmpl, group) {

    var table = tableTmpl.cloneNode(true);
    var circModRowTmpl = byName('circ-mod-entry-tbody', table).removeChild(byName('circ-mod-entry-row', table));
    circModGroupTables.push(table);

    var entries = [];
    if(group) {
        entries = new openils.PermaCrud().search('ccmcmtm', {circ_mod_test : group.id()});
        table.setAttribute('group', group.id());
        circModGroupCache[group.id()] = group;
        circModEntryCache[group.id()] = entries;
    }

    function addMod(code, name) {
        name = name || code; // XXX
        var row = circModRowTmpl.cloneNode(true);
        byName('circ-mod', row).innerHTML = name;
        byName('circ-mod', row).setAttribute('code', code);
        byName('circ-mod-entry-tbody', table).appendChild(row);
        byName('remove-circ-mod', row).onclick = function() {
            byName('circ-mod-entry-tbody', table).removeChild(row);
        }
    }

    dojo.forEach(entries, function(e) { addMod(e.circ_mod()); });

    byName('circ-mod-count', table).value = (group) ? group.items_out() : 0;

    var selector = new openils.widget.AutoFieldWidget({
        fmClass : 'ccmcmtm',
        fmField : 'circ_mod',
        parentNode : byName('circ-mod-selector', table)
    });
    selector.build();

    byName('add-circ-mod', table).onclick = function() {
        addMod(selector.widget.attr('value'), selector.widget.attr('displayedValue'));
    }

    node.insertBefore(table, byName('add-circ-mod-group-span', node));
    node.insertBefore(dojo.create('hr'), byName('add-circ-mod-group-span', node));
}

function applyCircModChanges() {
    var pcrud = new openils.PermaCrud();
    progressDialog.show(true);

    for(var idx in circModGroupTables) {
        var table = circModGroupTables[idx];
        var gp = table.getAttribute('group');

        var count = byName('circ-mod-count', table).value;
        var mods = [];
        var entries = [];

        dojo.forEach(dojo.query('[name=circ-mod]', table), function(td) { 
            mods.push(td.getAttribute('code'));
        });

        var group = circModGroupCache[gp];

        if(!group) {

            group = new fieldmapper.ccmcmt();
            group.isnew(true);
            dojo.forEach(mods, function(mod) {
                var entry = new fieldmapper.ccmcmtm();
                entry.isnew(true);
                entry.circ_mod(mod);
                entries.push(entry);
            });


        } else {

            var existing = circModEntryCache[group.id()];
            dojo.forEach(mods, function(mod) {
                
                // new circ mod for this group
                if(!existing.filter(function(i){ return (i.circ_mod() == mod)})[0]) {
                    var entry = new fieldmapper.ccmcmtm();
                    entry.isnew(true);
                    entry.circ_mod(mod);
                    entries.push(entry);
                    entry.circ_mod_test(group.id());
                }
            });

            dojo.forEach(existing, function(eMod) {
                if(!mods.filter(function(i){ return (i == eMod.circ_mod()) })[0]) {
                    eMod.isdeleted(true);
                    entries.push(eMod);
                }
            });
        }

        group.items_out(count);
        group.matchpoint(matchPoint);

        if(group.isnew()) {

            pcrud.create(group, {
                oncomplete : function(r) {
                    var group = openils.Util.readResponse(r);
                    dojo.forEach(entries, function(e) { e.circ_mod_test(group.id()) } );
                    pcrud.create(entries, {
                        oncomplete : function() {
                            progressDialog.hide();
                        }
                    });
                }
            });

        } else {

            pcrud.update(group, {
                oncomplete : function(r) {
                    openils.Util.readResponse(r);
                    var newOnes = entries.filter(function(e) { return e.isnew() });
                    var delOnes = entries.filter(function(e) { return e.isdeleted() });
                    if(!delOnes.length && !newOnes.length) {
                        progressDialog.hide();
                        return;
                    }
                    if(newOnes.length) {
                        pcrud.create(newOnes, {
                            oncomplete : function() {
                                if(delOnes.length) {
                                    pcrud.delete(delOnes, {
                                        oncomplete : function() {
                                            progressDialog.hide();
                                        }
                                    });
                                } else {
                                    progressDialog.hide();
                                }
                            }
                        });
                    } else {
                        pcrud.delete(delOnes, {
                            oncomplete : function() {
                                progressDialog.hide();
                            }
                        });
                    }
                }
            });
        }
    }
}

openils.Util.addOnLoad(load);


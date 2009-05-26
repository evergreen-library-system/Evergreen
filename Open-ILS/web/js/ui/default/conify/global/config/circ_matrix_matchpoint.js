dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');

var circModEditor = null;
var circModGroupTables = [];

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

    byName('add-circ-mod-group', node).onclick = function() {
        addCircModGroup(node, tableTmpl)
    }

    var group = null;
    if(editPane.mode == 'update') {
        //group = 
    } 

    editPane.domNode.appendChild(node);
}


function addCircModGroup(node, tableTmpl, group) {

    var table = tableTmpl.cloneNode(true);
    var circModRowTmpl = byName('circ-mod-entry-tbody', table).removeChild(byName('circ-mod-entry-row', table));
    circModGroupTables.push(table);

    function addMod(code, name) {
        var row = circModRowTmpl.cloneNode(true);
        byName('circ-mod', row).innerHTML = name;
        byName('circ-mod', row).setAttribute('code', code);
        byName('circ-mod-entry-tbody', table).appendChild(row);
        byName('remove-circ-mod', row).onclick = function() {
            byName('circ-mod-entry-tbody', table).removeChild(row);
        }
    }

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

    for(var idx in circModGroupTables) {
        var table = circModGroupTables[idx];

        var count = byName('circ-mod-count', table).value;
        var mods = [];
        dojo.forEach(dojo.query('[name=circ-mod]', table), function(td) { 
            mods.push(td.getAttribute('code'));
        });

        alert(count + ' : ' + mods);
    }
}

openils.Util.addOnLoad(load);


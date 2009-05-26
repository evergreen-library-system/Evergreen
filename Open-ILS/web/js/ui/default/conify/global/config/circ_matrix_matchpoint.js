dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');

var circModEditor = null;

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

    // loop over mods
    //
    
    function addMod(mod) {
        var row = circModRowTmpl.cloneNode(true);
        byName('circ-mod', row).innerHTML = mod;
        byName('circ-mod-entry-tbody', table).appendChild(row);
    }

    new openils.widget.AutoFieldWidget({
        fmClass : 'ccmcmt',
        fmField : 'items_out',
        fmObject : group,
        parentNode : byName('circ-mod-count', table)
    }).build();

    var selector = new openils.widget.AutoFieldWidget({
        fmClass : 'ccmcmtm',
        fmField : 'circ_mod',
        parentNode : byName('circ-mod-selector', table)
    });
    selector.build();

    byName('add-circ-mod', table).onclick = function() {
        addMod(selector.widget.attr('value'));
    }

    node.insertBefore(table, byName('add-circ-mod-group', node));
    node.insertBefore(dojo.create('hr'), byName('add-circ-mod-group', node));
}

openils.Util.addOnLoad(load);


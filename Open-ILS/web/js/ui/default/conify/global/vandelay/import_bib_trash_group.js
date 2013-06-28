dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.FlattenerGrid');
dojo.require('openils.widget.OrgUnitFilteringSelect');


function init() {
    if (!grp_id) return;

    new openils.PermaCrud().retrieve(
        'vibtg', grp_id, {
            oncomplete : function(r) {
                init2(openils.Util.readResponse(r));
            }
        }
    );
}

function init2(grp) {
    dojo.byId('trash-group-name').innerHTML = grp.label();
    tfGrid.overrideEditWidgets.grp = new dijit.form.TextBox({
        value : grp.id(),
        disabled : true
    });
}

function format_grp(val) {
    return '<a href="' + location.href + 
        '/' + encodeURIComponent(val) + '">' + val + '</a>';
}

openils.Util.addOnLoad(init);

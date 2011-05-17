dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

function load(){
    cmGrid.overrideWidgetArgs.prefix = {hrbefore : true};
    cmGrid.overrideWidgetArgs.asset = {hrbefore: true};
    cmGrid.loadAll({order_by:{cbc:'org_unit'}});
}

openils.Util.addOnLoad(load);


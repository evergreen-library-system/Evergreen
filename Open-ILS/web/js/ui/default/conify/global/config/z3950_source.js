dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.AutoGrid');
var zsList;

function buildZSGrid() {
    zsGrid.loadAll({order_by:{czs : 'name'}});
}

openils.Util.addOnLoad(buildZSGrid);



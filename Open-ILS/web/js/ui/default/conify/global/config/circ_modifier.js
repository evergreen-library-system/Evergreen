dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.widget.AutoGrid');

var cmCache = {};

function buildCMGrid() {

 cmGrid.overrideEditWidgets.sip2_media_type = sip2Selector;   
 cmGrid.loadAll({order_by:{ccm : 'name'}});
}
   
openils.Util.addOnLoad(buildCMGrid);



         
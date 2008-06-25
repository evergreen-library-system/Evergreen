dojo.require("dijit.Dialog");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.Grid');
dojo.require('openils.acq.PO');
dojo.require('openils.Event');
dojo.require('openils.User');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.acq.Provider');
dojo.require('openils.acq.Lineitems');
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');

var PO = null;
var lineitems = [];

function getOrgInfo(rowIndex) {
    data = poGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.owner).shortname();
}

function getProvider(rowIndex) {
    data = poGrid.model.getRow(rowIndex);
    if(!data) return;
    return openils.acq.Provider.retrieve(data.provider).code();
}

function getPOOwner(rowIndex) {
    data = poGrid.model.getRow(rowIndex);
    if(!data) return;
    return new openils.User({id:data.owner}).user.usrname();
}

function getDateTimeField(rowIndex) {
    data = poGrid.model.getRow(rowIndex);
    if(!data) return;
    var date = dojo.date.stamp.fromISOString(data[this.field]);
    return dojo.date.locale.format(date, {formatLength:'medium'});
}

function loadPOGrid() {
    if(!PO) return;
    var store = new dojo.data.ItemFileReadStore({data:acqpo.toStoreData([PO])});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    poGrid.setModel(model);
    poGrid.update();
}

function loadLIGrid() {
    if(liGrid.isLoaded) return;

    function load(po) {
        lineitems = po.lineitems();
        var store = new dojo.data.ItemFileReadStore({data:jub.toStoreData(lineitems)});
        var model = new dojox.grid.data.DojoData(
            null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
        JUBGrid.populate(liGrid, model, lineitems)
    }

    openils.acq.PO.retrieve(poId, load, {flesh_lineitems:1, clear_marc:1});
    liGrid.isLoaded = true;
}

function loadPage() {
    fetchPO();
}

function fetchPO() {
    openils.acq.PO.retrieve(poId, 
        function(po) {
            PO = po;
            loadPOGrid();
        },
        {flesh_lineitem_count:1}
    );
}

dojo.addOnLoad(loadPage);

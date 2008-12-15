dojo.require("dijit.Dialog");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.acq.PO');
dojo.require('openils.Event');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.acq.Provider');
dojo.require('openils.acq.Lineitem');
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');

var PO = null;
var lineitems = [];

function getOrgInfo(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item , 'ordering_agency')
    return fieldmapper.aou.findOrgUnit(data).shortname();
}

function getProvider(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, 'provider');
    return openils.acq.Provider.retrieve(data).code();
}

function getPOOwner(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, 'owner');
    return new openils.User({id:data}).user.usrname();
}

function getDateTimeField(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, this.field);
    var date = dojo.date.stamp.fromISOString(data);
    return dojo.date.locale.format(date, {formatLength:'medium'});
}

function loadPOGrid() {
    if(!PO) return '';
    var store = new dojo.data.ItemFileReadStore({data:acqpo.toStoreData([PO])});
    poGrid.setStore(store);
    poGrid.render();
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

openils.Util.addOnLoad(loadPage);

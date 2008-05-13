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
dojo.require('openils.acq.Picklist');

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
    return openils.acq.Provider.retrieve(data.provider).name();
}

function getPOOwner(rowIndex) {
    data = poGrid.model.getRow(rowIndex);
    if(!data) return;
    return new openils.User({id:data.owner}).user.usrname();
}

function getJUBTitle(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return '';
    for(var i in lineitems) {
        var li = lineitems[i];
        if(li.id() == data.id) {
            openils.acq.Picklist.cache[data.id] = li;
            return openils.acq.Picklist.find_attr(data.id, 'title', 'lineitem_marc_attr_definition')
        }
    }
}

function getJUBPrice(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return;
    for(var i in lineitems) {
        var li = lineitems[i];
        if(li.id() == data.id) {
            openils.acq.Picklist.cache[data.id] = li;
            return openils.acq.Picklist.find_attr(data.id, 'price', 'lineitem_marc_attr_definition')
        }
    }
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

    function load(r) {
        var po = r.recv().content();
        lineitems = po.lineitems();
        var store = new dojo.data.ItemFileReadStore({data:jub.toStoreData(lineitems)});
        var model = new dojox.grid.data.DojoData(
            null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
        liGrid.setModel(model);
        liGrid.update();
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, poId, {flesh_lineitems:1, clear_marc:1}], /* XXX PAGING */
            oncomplete : load
        }
    );
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
        }
    );
}

dojo.addOnLoad(loadPage);

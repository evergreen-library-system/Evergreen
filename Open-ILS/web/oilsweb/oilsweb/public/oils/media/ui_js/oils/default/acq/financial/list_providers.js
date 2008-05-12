dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');

dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.acq.Provider');
dojo.require("fieldmapper.OrgUtils");

function getOrgInfo(rowIndex) {
    data = providerListGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.owner).shortname();
}

function loadProviderGrid() {
    openils.acq.Provider.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
            var model = new dojox.grid.data.DojoData(null, store, 
                {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
            providerListGrid.setModel(model);
            providerListGrid.update();
        }
    );
}

dojo.addOnLoad(loadProviderGrid);

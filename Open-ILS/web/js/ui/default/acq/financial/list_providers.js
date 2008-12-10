dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.acq.Provider');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.widget.OrgUnitFilteringSelect');

function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'owner'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();
}

function loadProviderGrid() {
    openils.acq.Provider.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
           
            providerListGrid.setStore(store);
            providerListGrid.render();
        }
    );
}

function createProvider(fields) {
    openils.acq.Provider.create(fields, function(){loadProviderGrid()});
}


openils.Util.addOnLoad(loadProviderGrid);

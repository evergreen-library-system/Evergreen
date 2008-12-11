dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
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
    var store = new dojo.data.ItemFileWriteStore({data:acqpro.initStoreData()});
    providerListGrid.setStore(store);
    providerListGrid.render();
    
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.provider.org.retrieve'],
        {   async: true,
            params: [openils.User.authtoken],
            onresponse : function(r) {
                if( lp = openils.Util.readResponse(r)) {
                    openils.acq.Provider.cache[lp.id()] = lp;
                    store.newItem(acqpro.itemToStoreData(lp));
                }
            }
        }       
        
    );
}

function createProvider(fields) {
    openils.acq.Provider.create(fields, function(){loadProviderGrid()});
}


openils.Util.addOnLoad(loadProviderGrid);

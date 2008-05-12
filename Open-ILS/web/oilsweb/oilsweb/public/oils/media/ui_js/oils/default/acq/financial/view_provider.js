dojo.require("dijit.Dialog");
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.Grid');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.Provider');
dojo.require('openils.Event');
dojo.require('openils.User');

var provider = null;

function getOrgInfo(rowIndex) {
    data = providerGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.owner).shortname();
}

function loadProviderGrid() {
    var store = new dojo.data.ItemFileReadStore({data:acqpro.toStoreData([provider])});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    providerGrid.setModel(model);
    providerGrid.update();
}

function fetchProvider() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.provider.retrieve'],
        {   async: true,
            params: [ openils.User.authtoken, providerId ],
            oncomplete: function(r) {
                provider = r.recv().content();
                loadProviderGrid(provider);
            }
        }
    );
}

dojo.addOnLoad(fetchProvider);


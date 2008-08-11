dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('openils.acq.FundingSource');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');
dojo.require('openils.Event');

function getOrgInfo(rowIndex) {
    data = fundingSourceListGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.owner).shortname();
}

function getBalanceInfo(rowIndex) {
    data = fundingSourceListGrid.model.getRow(rowIndex);
    if(!data) return;
    return new String(openils.acq.FundingSource.cache[data.id].summary().balance);
}

function loadFSGrid() {
    openils.acq.FundingSource.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
            var model = new dojox.grid.data.DojoData(null, store, 
                {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
            fundingSourceListGrid.setModel(model);
            fundingSourceListGrid.update();
        }
    );
}

dojo.addOnLoad(loadFSGrid);

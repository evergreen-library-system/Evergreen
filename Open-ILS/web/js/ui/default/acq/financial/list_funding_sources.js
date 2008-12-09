dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('openils.acq.FundingSource');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dojox.grid.DataGrid');
dojo.require('openils.Event');
dojo.require('openils.Util');

function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'owner'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue( item, 'id');   
    return new String(openils.acq.FundingSource.cache[data].summary().balance);
}

function loadFSGrid() {
    openils.acq.FundingSource.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
            fundingSourceListGrid.setStore(store);
            fundingSourceListGrid.render();
        }
    );
}

openils.Util.addOnLoad(loadFSGrid);

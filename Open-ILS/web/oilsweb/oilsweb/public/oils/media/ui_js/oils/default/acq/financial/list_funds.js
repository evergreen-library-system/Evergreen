dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');

dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.acq.Fund');

var globalUser = new openils.User();

function getOrgInfo(rowIndex) {
    data = fundListGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.org).shortname();
}

function getBalanceInfo(rowIndex) {
    data = fundListGrid.model.getRow(rowIndex);
    if(!data) return;
    return new String(openils.acq.Fund.cache[data.id].summary().combined_balance);
}


function loadFundGrid() {
    openils.acq.Fund.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
            var model = new dojox.grid.data.DojoData(null, store, 
                {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
            fundListGrid.setModel(model);
            fundListGrid.update();
        }
    );
}

dojo.addOnLoad(loadFundGrid);


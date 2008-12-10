dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');

dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.acq.Fund');

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

            var yearStore = {identifier:'year', name:'year', items:[]};

            var added = {};
            for(var i = 0; i < storeData.items.length; i++) {
                var year = storeData.items[i].year;
                if(!(year in added)) {
                    yearStore.items.push({year:year});
                    added[year] = 1;
                }
            }
            yearStore.items = yearStore.items.sort().reverse();
            fundFilterYearSelect.store = new dojo.data.ItemFileReadStore({data:yearStore});
            var today = new Date().getFullYear().toString();
            if(today in added)
                fundFilterYearSelect.setValue(today);
        }
    );
}

function filterGrid() {
    var year = fundFilterYearSelect.getValue();
    if(year) 
        fundListGrid.model.query = {year:year};
    else
        fundListGrid.model.query = {id:'*'};
    fundListGrid.model.refresh();
    fundListGrid.update();
}

openils.Util.addOnLoad(loadFundGrid);


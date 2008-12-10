dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.acq.Fund');

function getOrgInfo(rowIndex, item) {
     
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'org'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue( item, 'id');   
    return new String(openils.acq.Fund.cache[data].summary().combined_balance);
}

function loadFundGrid() {
    openils.acq.Fund.createStore(
        function(storeData) {
            var store = new dojo.data.ItemFileReadStore({data:storeData});
            
            fundListGrid.setStore(store);
            fundListGrid.render();

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
        fundListGrid.query = {year:year};
    else
        fundListGrid.query = {id:'*'};
        fundListGrid.update();
}

openils.Util.addOnLoad(loadFundGrid);


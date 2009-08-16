dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.acq.Fund');
dojo.require('openils.widget.AutoGrid');

function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'org'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();
}

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var id = this.grid.store.getValue( item, 'id');   
    var fund = openils.acq.Fund.cache[id];
    if(fund && fund.summary()) 
        return fund.summary().combined_balance;
    return 0;
}

function loadFundGrid(year) {
    var yearStore = {identifier:'year', name:'year', items:[]};
    var yearsAdded = {}; /* don't duplicate the years in the selector */
    lfGrid.resetStore();

    if(!year) year = new Date().getFullYear().toString();

    lfGrid.dataLoader = function() { loadFundGrid(year); };

    fieldmapper.standardRequest(
       [ 'open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
       {    async: true,

            params: [
                openils.User.authtoken, 
                {year:year}, 
                {
                    flesh_summary:1, 
                    limit: lfGrid.displayLimit,
                    offset: lfGrid.displayOffset
                }
            ],

            onresponse : function(r) {
                if(lf = openils.Util.readResponse(r)) {
                   openils.acq.Fund.cache[lf.id()] = lf;
                   lfGrid.store.newItem(acqf.toStoreItem(lf));
                    var year = lf.year();
                    if(!(year in yearsAdded)) {
                        yearStore.items.push({year:year});
                        yearsAdded[year] = 1;
                    }
                }
            },

            oncomplete : function(r) {
                yearStore.items = yearStore.items.sort().reverse();
                fundFilterYearSelect.store = new dojo.data.ItemFileReadStore({data:yearStore});
                var today = new Date().getFullYear().toString();

                if(today in yearsAdded)
                    fundFilterYearSelect.setValue(today);

                lfGrid.hideLoadProgressIndicator();

                dojo.connect(
                    fundFilterYearSelect, 
                    'onChange', 
                    function() {
                        loadFundGrid(fundFilterYearSelect.getValue());
                    }
                );
            }
        }
    );
}


openils.Util.addOnLoad(loadFundGrid);


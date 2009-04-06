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
    var data = this.grid.store.getValue( item, 'id');   
    return new String(openils.acq.Fund.cache[data].summary().combined_balance);
}

function loadFundGrid() {
    var yearStore = {identifier:'year', name:'year', items:[]};
    var yearsAdded = {}; /* don't duplicate the years in the selector */
    
    fieldmapper.standardRequest(
       [ 'open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
       {    async: true,
            params: [openils.User.authtoken, null, {flesh_summary:1}],
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
                // sort the unique list of years and set the selector to "now" if possible
                yearStore.items = yearStore.items.sort().reverse();
                fundFilterYearSelect.store = new dojo.data.ItemFileReadStore({data:yearStore});
                var today = new Date().getFullYear().toString();
                if(today in yearsAdded)
                    fundFilterYearSelect.setValue(today);
            }
        }
    );
}

function filterGrid() {
    console.log('filtergrid called');
    var year = fundFilterYearSelect.getValue();
    console.log(year);
    if(year) 
        lfGrid.setQuery({year:year});
    else
        lfGrid.setQuery({id:'*'});
    
    lfGrid.update();
}

openils.Util.addOnLoad(loadFundGrid);


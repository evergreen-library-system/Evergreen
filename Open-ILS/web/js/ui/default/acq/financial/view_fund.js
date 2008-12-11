dojo.require("dijit.Dialog");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.DataGrid');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.Fund');
dojo.require('openils.acq.FundingSource');
dojo.require('openils.Event');
dojo.require('openils.User');
dojo.require('openils.Util');

var fund = null;

function getSummaryInfo(rowIndex, item) {
    if(!item) return'';
    return new String(fund.summary()[this.field]);
}

function createAllocation(fields) {
    fields.fund = fundID;
    if(isNaN(fields.percent)) fields.percent = null;
    if(isNaN(fields.amount)) fields.amount = null;
    openils.acq.Fund.createAllocation(fields, 
        function(r){location.href = location.href;});
}
function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'org'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}

function getXferDest(rowIndex, item) {
    if(!item) return '';
    var xfer_destination = this.grid.store.getValue(item, 'xfer_destination');
    if(!(item && xfer_destination)) return '';
    return xfer_destination;
}

function loadFundGrid() {
    var store = new dojo.data.ItemFileReadStore({data:acqf.toStoreData([fund])});
    fundGrid.setStore(store);
    fundGrid.render();
}

function loadAllocationGrid() {
    if(fundAllocationGrid.isLoaded) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfa.toStoreData(fund.allocations())});
    fundAllocationGrid.setStore(store);
    fundAllocationGrid.render();
    fundAllocationGrid.isLoaded = true;
}

function loadDebitGrid() {
    if(fundDebitGrid.isLoaded) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfa.toStoreData(fund.debits())});
    fundDebitGrid.setStore(store);
    fundDebitGrid.render();
    fundDebitGrid.isLoaded = true;
}

function fetchFund() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.retrieve'],
        {   async: true,
            params: [
                openils.User.authtoken, fundID, 
                {flesh_summary:1, flesh_allocations:1, flesh_debits:1} 
                /* TODO grab allocations and debits only on as-needed basis */
            ],
            oncomplete: function(r) {
                fund = r.recv().content();
                loadFundGrid(fund);
            }
        }
    );
}

openils.Util.addOnLoad(fetchFund);

dojo.require("dijit.Dialog");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.Grid');

dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.Fund');
dojo.require('openils.acq.FundingSource');
dojo.require('openils.Event');
dojo.require('openils.User');

var fund = null;

function getSummaryInfo(rowIndex) {
    switch(this.index) {
        case 4: return new String(fund.summary().combined_balance);
        case 5: return new String(fund.summary().allocation_total);
        case 6: return new String(fund.summary().spent_balance);
        case 7: return new String(fund.summary().debit_total);
        case 8: return new String(fund.summary().spent_total);
        case 9: return new String(fund.summary().encumbrance_total);
    }
}

function createAllocation(fields) {
    fields.fund = fundID;
    if(isNaN(fields.percent)) fields.percent = null;
    if(isNaN(fields.amount)) fields.amount = null;
    //openils.acq.Fund.createAllocation(fields, resetPage);
    openils.acq.Fund.createAllocation(fields, 
        function(r){location.href = location.href;});
}

function getOrgInfo(rowIndex) {
    data = fundGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.org).shortname();
}


function loadFundGrid() {
    var store = new dojo.data.ItemFileReadStore({data:acqf.toStoreData([fund])});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    fundGrid.setModel(model);
    fundGrid.update();
}

function loadAllocationGrid() {
    if(fundAllocationGrid.isLoaded) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfa.toStoreData(fund.allocations())});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    fundAllocationGrid.setModel(model);
    fundAllocationGrid.update();
    fundAllocationGrid.isLoaded = true;
}

function loadDebitGrid() {
    if(fundDebitGrid.isLoaded) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfa.toStoreData(fund.debits())});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    fundDebitGrid.setModel(model);
    fundDebitGrid.update();
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

dojo.addOnLoad(fetchFund);

dojo.require("dijit.Dialog");
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require("dijit.form.FilteringSelect");
dojo.require("dijit.form.Textarea");
dojo.require("dijit.form.CurrencyTextBox");
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.FundingSource');
dojo.require('openils.acq.Fund');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');
    
var ses = new OpenSRF.ClientSession('open-ils.acq');
var fundingSource = null;

function resetPage() {
    fundingSource = null;
    fsCreditGrid.isLoaded = false;
    fsAllocationGrid.isLoaded = false;
    loadFS();
}

function getFund(rowIndex, item) {
    return '';
    //return '<a href="[% ctx.base_path %]/acq/fund/view/'+fund.id()+'">'+fund.code()+'</a>';
}


/** creates a new funding_source_credit from the dialog ----- */
function applyFSCredit(fields) {
    fields.funding_source = fundingSourceID;
    openils.acq.FundingSource.createCredit(fields, resetPage);
}

function applyFSAllocation(fields) {
    fields.funding_source = fundingSourceID;
    if(isNaN(fields.amount)) fields.amount = null;
    openils.acq.Fund.createAllocation(fields, resetPage);
}

/** fetch the fleshed funding source ----- */
function loadFS() {
    var req = ses.request(
        'open-ils.acq.funding_source.retrieve', 
        openils.User.authtoken, fundingSourceID, 
        {flesh_summary:1, flesh_credits:1,flesh_allocations:1}
    );

    req.oncomplete = function(r) {
        var msg = req.recv();
        fundingSource = msg.content();
        var evt = openils.Event.parse(fundingSource);
        if(evt) {
            alert(evt);
            return;
        }
        loadFSGrid();
    }
    req.send();
}

/** Some grid rendering accessor functions ----- */
function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'owner'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}

function getSummaryInfo(rowIndex) {
    return new String(fundingSource.summary()[this.field]);
}

function getFund(rowIndex, item) {
    if(item) {
        var fId = this.grid.store.getValue(item, 'fund');
        return openils.acq.Fund.retrieve(fId);
    }
}

function formatFund(fund) {
    if(fund) {
        return '<a href="' + oilsBasePath + '/acq/fund/view/'+fund.id()+'">'+fund.code()+'</a>';
    }
}

/** builds the credits grid ----- */
function loadFSGrid() {
    if(!fundingSource) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfs.toStoreData([fundingSource])});
    fundingSourceGrid.setStore(store);
    fundingSourceGrid.render();
}


/** builds the credits grid ----- */
function loadCreditGrid() {
    if(fsCreditGrid.isLoaded) return;
    fsCreditGrid.loadAll({order_by : {acqfscred :  'effective_date DESC'}});
    fsCreditGrid.isLoaded = true;
}

function loadAllocationGrid() {
    if(fsAllocationGrid.isLoaded) return;
    fsAllocationGrid.loadAll({order_by : {acqfa :  'create_time DESC'}});
    fsAllocationGrid.isLoaded = true;
}

openils.Util.addOnLoad(loadFS);

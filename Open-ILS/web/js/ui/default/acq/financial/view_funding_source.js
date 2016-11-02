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

function resetPage(also_load_grid) {
    fundingSource = null;
    fsCreditGrid.isLoaded = false;
    fsAllocationGrid.isLoaded = false;
    loadFS(also_load_grid);
}

function getFund(rowIndex, item) {
    return '';
    //return '<a href="[% ctx.base_path %]/acq/fund/view/'+fund.id()+'">'+fund.code()+'</a>';
}


/** creates a new funding_source_credit from the dialog ----- */
function applyFSCredit(fields) {
    fields.funding_source = fundingSourceID;
    openils.acq.FundingSource.createCredit(
        fields, function() { resetPage(loadCreditGrid); }
    );
}

function applyFSAllocation(fields) {
    fields.funding_source = fundingSourceID;
    if(isNaN(fields.amount)) fields.amount = null;
    openils.acq.Fund.createAllocation(
        fields, function() { resetPage(loadAllocationGrid); }
    );
}

/** fetch the fleshed funding source ----- */
function loadFS(also_load_grid) {
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
        if (typeof(also_load_grid) == "function")
            also_load_grid(true /* reset_first */);
    }
    req.send();

    new openils.widget.AutoFieldWidget({
        "fmField": "fund",
        /* We're not really using LIDs here, we just need some class
         * that has a fund field to take advantage of AutoFieldWidget's
         * magic. */
        "fmClass": "acqlid",
        "labelFormat": ["${0} (${1})", "code", "year"],
        "searchFormat": ["${0} (${1})", "code", "year"],
        "searchFilter": {"active": "t"},
        "searchOptions": {"order_by" : {"acqf":"year DESC, code"}},
        "parentNode": dojo.byId("oils-acq-funding-source-fund-allocate"),
        "orgLimitPerms": ["MANAGE_FUND"], //???
        "dijitArgs": { "name" : "fund" }
    }).build(function(w, ww) {});
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

/** builds the summary grid ----- */
function loadFSGrid() {
    if(!fundingSource) return;
    var store = new dojo.data.ItemFileReadStore({data:acqfs.toStoreData([fundingSource])});
    fundingSourceGrid.setStore(store);
    fundingSourceGrid.render();
}


/** builds the credits grid ----- */
function loadCreditGrid(reset_first) {
    if (fsCreditGrid.isLoaded) return;
    if (reset_first) fsCreditGrid.resetStore();
    fsCreditGrid.loadAll(
        {"order_by": {"acqfscred": "effective_date DESC"}},
        {"funding_source": fundingSource.id()}
    );
    fsCreditGrid.isLoaded = true;
}

function loadAllocationGrid(reset_first) {
    if (fsAllocationGrid.isLoaded) return;
    if (reset_first) fsCreditGrid.resetStore();
    fsAllocationGrid.loadAll(
        {"order_by": {"acqfa": "create_time DESC"}},
        {"funding_source": fundingSource.id()}
    );
    fsAllocationGrid.isLoaded = true;
}

openils.Util.addOnLoad(loadFS);

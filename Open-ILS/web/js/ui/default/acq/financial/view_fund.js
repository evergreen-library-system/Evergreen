dojo.require("dijit.Dialog");
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.DataGrid');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require("dijit.form.CheckBox");
dojo.require('dojo.data.ItemFileReadStore');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.Fund');
dojo.require('openils.acq.FundingSource');
dojo.require('openils.Event');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require("openils.widget.AutoFieldWidget");
dojo.require("openils.widget.AutoGrid");

var fund = null;
var tagManager;
var xferManager;

function getSummaryInfo(rowIndex, item) {
    if(!item) return'';
    return new String(fund.summary()[this.field]);
}

function createAllocation(fields) {
    fields.fund = fundID;
    if(isNaN(fields.amount)) fields.amount = null;
    openils.acq.Fund.createAllocation(fields, 
        function(r){location.href = location.href;});
}
function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'org'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}


function getFundingSource(rowIndex, item) {
    if(item) {
        var fsId = this.grid.store.getValue(item, 'funding_source');
        return openils.acq.FundingSource.retrieve(fsId);
    }
}

function formatFundingSource(fs) {
    if(fs) {
        return '<a href="' + oilsBasePath + '/acq/funding_source/view/'+fs.id()+'">'+fs.code()+'</a>';
    }
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
    /* XXX If we want to show allocating user with a username instead of just
     * ID#, the following pcrud search will have to be replaced with an API
     * call. */
    fundAllocationGrid.loadAll({order_by : {acqfa :  'create_time DESC'}}, {fund : fundID});
    fundAllocationGrid.isLoaded = true;
}

function loadDebitGrid() {
    if(fundDebitGrid.isLoaded) return;
    fundDebitGrid.loadAll({order_by : {acqfdeb :  'create_time DESC'}}, {fund : fundID});
    fundDebitGrid.isLoaded = true;
}

function fetchFund() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.retrieve'],
        {   async: true,
            params: [
                openils.User.authtoken, fundID, 
                {flesh_summary:1, flesh_tags:1} 
            ],
            oncomplete: function(r) {
                fund = r.recv().content();
                loadFundGrid(fund);
            }
        }
    );
}

function TransferManager() {
    var self = this;

    this._init = function() {
        new openils.widget.AutoFieldWidget({
            "fmField": "fund",
            /* We're not really using LIDs here, we just need some class
             * that has a fund field to take advantage of AutoFieldWidget's
             * magic. */
            "fmClass": "acqlid",
            "labelFormat": ["${0} (${1})", "code", "year"],
            "searchFormat": ["${0} (${1})", "code", "year"],
            "searchFilter": {"active": "t"}, /* consider making it possible
                                                to select inactive? */
            "parentNode": dojo.byId("oils-acq-fund-xfer-d-selector"),
            "orgLimitPerms": ["ADMIN_ACQ_FUND"], /* XXX is there a more
                                                    appropriate permission
                                                    for this? */
            "dijitArgs": {
                "onChange": function() {
                    openils.Util[
                        this.item.currency_type == fund.currency_type() ?
                            "hide" : "show"
                    ]("oils-acq-fund-xfer-dest-amount", "table-row");
                }
            },
            "forceSync": true
        }).build(function(w, ww) { self.fundSelector = w; });

        dijit.byId("oils-acq-fund-xfer-same-o-d").onChange = function() {
            dijit.byId("oils-acq-fund-xfer-d-amount").attr(
                "disabled", this.attr("checked")
            );
        }
    };

    this._init();

    this.clearFundSelector = function() {
        if (this.fundSelector.attr("value"))
            this.fundSelector.attr("value", "");
    };

    this.setFundName = function(fund) {
        dojo.byId("oils-acq-fund-xfer-name-fund").innerHTML =
            fund.code() + " (" + fund.year() + ") / " + fund.name();
    };

    this.submit = function() {
        var values = xferDialog.getValues();
        var dfund = this.fundSelector.item;
        var dfund_id = typeof(dfund.id) == "object" ? dfund.id[0] : dfund.id;

        if (dfund_id == fund.id()) {
            alert(localeStrings.FUND_XFER_SAME_SOURCE_AND_DEST);
            return false;
        }
        if (confirm(localeStrings.FUND_XFER_CONFIRM)) {
            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.funds.transfer_money"], {
                    "params": [
                        openils.User.authtoken,
                        fund.id(),
                        values.o_amount,
                        dfund_id,
                        (dfund.currency_type != fund.currency_type() &&
                            values.same_o_d.length) ? null : values.d_amount,
                        values.note
                    ],
                    "async": true,
                    "oncomplete": function(r) {
                        if (openils.Util.readResponse(r) == 1) {
                            location.href = location.href;
                        }
                    }
                }
            );
        }
    };
}

function load() {
    tagManager = new TagManager(dojo.byId("oils-acq-tag-manager-display"));
    tagManager.prepareTagSelector(tagSelector);

    xferManager = new TransferManager();

    fetchFund();
}

openils.Util.addOnLoad(load);

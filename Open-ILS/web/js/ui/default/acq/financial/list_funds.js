dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('dijit.form.Button');
dojo.require('dijit.TooltipDialog');
dojo.require('dijit.form.DropDownButton');
dojo.require('dijit.form.CheckBox');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.CGI');
dojo.require('openils.acq.Fund');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.ProgressDialog');
dojo.require('fieldmapper.OrgUtils');
dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var contextOrg;
var rolloverResponses;
var rolloverMode = false;

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var id = this.grid.store.getValue( item, 'id');   
    var fund = openils.acq.Fund.cache[id];
    if(fund && fund.summary()) 
        return fund.summary().combined_balance;
    return 0;
}

function initPage() {

    contextOrg = openils.User.user.ws_ou();

    var connect = function() {
        dojo.connect(contextOrgSelector, 'onChange',
            function() {
                contextOrg = this.attr('value');
                dojo.byId('oils-acq-rollover-ctxt-org').innerHTML = 
                    fieldmapper.aou.findOrgUnit(contextOrg).shortname();
                rolloverMode = false;
                gridDataLoader();
            }
        );
    };

    dojo.connect(refreshButton, 'onClick', function() { rolloverMode = false; gridDataLoader(); });

    new openils.User().buildPermOrgSelector(
        'ADMIN_ACQ_FUND', contextOrgSelector, contextOrg, connect);

    dojo.byId('oils-acq-rollover-ctxt-org').innerHTML = 
        fieldmapper.aou.findOrgUnit(contextOrg).shortname();

    loadYearSelector();
    lfGrid.dataLoader = gridDataLoader;
    loadFundGrid(new openils.CGI().param('year') || new Date().getFullYear().toString());
}

function gridDataLoader() {
    lfGrid.resetStore();
    if(rolloverMode) {
        var offset = lfGrid.displayOffset;
        for(var i = offset; i < (offset + lfGrid.displayLimit - 1); i++) {
            var fund = rolloverResponses[i];
            if(!fund) break;
            lfGrid.store.newItem(fieldmapper.acqf.toStoreItem(fund));
        }
    } else {
        loadFundGrid();
    }
}

function loadFundGrid(year) {

    openils.Util.hide('acq-fund-list-rollover-summary');
    year = year || fundFilterYearSelect.attr('value');

    fieldmapper.standardRequest(
       [ 'open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
       {    async: true,

            params: [
                openils.User.authtoken, 
                {year : year, org : fieldmapper.aou.descendantNodeList(contextOrg, true)}, 
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
                }
            },

            oncomplete : function(r) {
                lfGrid.hideLoadProgressIndicator();
            }
        }
    );
}

function loadYearSelector() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.org.years.retrieve'],
        {   async : true,
            params : [openils.User.authtoken],
            oncomplete : function(r) {

                var yearList = openils.Util.readResponse(r);
                if(!yearList) return;
                yearList = yearList.map(function(year){return {year:year+''};}); // dojo wants strings

                var yearStore = {identifier:'year', name:'year', items:yearList};
                yearStore.items = yearStore.items.sort().reverse();
                fundFilterYearSelect.store = new dojo.data.ItemFileWriteStore({data:yearStore});

                // default to this year
                fundFilterYearSelect.setValue(new Date().getFullYear().toString());

                dojo.connect(
                    fundFilterYearSelect, 
                    'onChange', 
                    function() { 
                        rolloverMode = false;
                        gridDataLoader();
                    }
                );
            }
        }
    );
}

function performRollover(args) {

    rolloverMode = true;
    progressDialog.show(true, "Processing...");
    rolloverResponses = [];

    var method = 'open-ils.acq.fiscal_rollover';

    if(args.rollover[0] == 'on') {
        method += '.combined';
    } else {
        method += '.propagate';
    }
        
    var dryRun = args.dry_run[0] == 'on';
    if(dryRun) method += '.dry_run';

    var count = 0;
    var amount_rolled = 0;
    var year = fundFilterYearSelect.attr('value'); // TODO alternate selector?
    
    fieldmapper.standardRequest(
        ['open-ils.acq', method],
        {
            async : true,

            params : [
                openils.User.authtoken, 
                year,
                contextOrg,
                (args.child_orgs[0] == 'on')
            ],

            onresponse : function(r) {
                var resp = openils.Util.readResponse(r);
                rolloverResponses.push(resp.fund);
                count += 1;
                amount_rolled += Number(resp.rollover_amount);
            }, 

            oncomplete : function() {
                
                var nextYear = Number(year) + 1;
                rolloverResponses = rolloverResponses.sort(
                    function(a, b) {
                        if(a.code() > b.code())
                            return 1;
                        return -1;
                    }
                )

                dojo.byId('acq-fund-list-rollover-summary-header').innerHTML = 
                    dojo.string.substitute(
                        localeStrings.FUND_LIST_ROLLOVER_SUMMARY,
                        [nextYear]
                    );

                dojo.byId('acq-fund-list-rollover-summary-funds').innerHTML = 
                    dojo.string.substitute(
                        localeStrings.FUND_LIST_ROLLOVER_SUMMARY_FUNDS,
                        [nextYear, count]
                    );

                dojo.byId('acq-fund-list-rollover-summary-rollover-amount').innerHTML = 
                    dojo.string.substitute(
                        localeStrings.FUND_LIST_ROLLOVER_SUMMARY_ROLLOVER_AMOUNT,
                        [nextYear, amount_rolled]
                    );

                if(!dryRun) {
                    openils.Util.hide('acq-fund-list-rollover-summary-dry-run');
                    
                    // add the new year to the year selector if it's not already there
                    fundFilterYearSelect.store.fetch({
                        query : {year : nextYear}, 
                        onComplete:
                            function(list) {
                                if(list && list.length > 0) return;
                                fundFilterYearSelect.store.newItem({year : nextYear});
                            }
                    });
                }

                openils.Util.show('acq-fund-list-rollover-summary');
                progressDialog.hide();
                gridDataLoader();
            }
        }
    );
}

openils.Util.addOnLoad(initPage);

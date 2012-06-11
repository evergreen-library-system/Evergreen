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
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.ProgressDialog');
dojo.require('fieldmapper.OrgUtils');
dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var contextOrg;
var rolloverResponses;
var rolloverMode = false;
var fundFleshFields = [
    'spent_balance', 
    'combined_balance', 
    'spent_total', 
    'encumbrance_total', 
    'debit_total', 
    'allocation_total'
];

var adminPermOrgs = [];
var cachedFunds = [];

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

    dojo.connect(refreshButton, 'onClick', 
        function() { rolloverMode = false; gridDataLoader(); });

    new openils.User().buildPermOrgSelector(
        ['ADMIN_ACQ_FUND', 'VIEW_FUND'], 
        contextOrgSelector, contextOrg, connect);

    dojo.byId('oils-acq-rollover-ctxt-org').innerHTML = 
        fieldmapper.aou.findOrgUnit(contextOrg).shortname();

    loadYearSelector();
    lfGrid.onItemReceived = function(item) {cachedFunds.push(item)};

    new openils.User().getPermOrgList(
        'ADMIN_ACQ_FUND',
        function(list) {
            adminPermOrgs = list;
            loadFundGrid(
                new openils.CGI().param('year') 
                    || new Date().getFullYear().toString());
        },
        true, true
    );
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

function getBalanceInfo(rowIdx, item) {
    if (!item) return '';
    var fundId = this.grid.store.getValue(item, 'id');
    var fund = cachedFunds.filter(function(f) { return f.id() == fundId })[0];
    var cb = fund.combined_balance();
    return cb ? cb.amount() : '0';
}

function loadFundGrid(year) {
    openils.Util.hide('acq-fund-list-rollover-summary');
    year = year || fundFilterYearSelect.attr('value');
    cachedFunds = [];

    lfGrid.loadAll(
        {
            flesh : 1,  
            flesh_fields : {acqf : fundFleshFields},
            
            // by default, sort funds I can edit to the front
            order_by : [
                {   'class' : 'acqf',
                    field : 'org',
                    compare : {'in' : adminPermOrgs},
                    direction : 'desc'
                },
                {   'class' : 'acqf',
                    field : 'name'
                }
            ]
        }, {   
            year : year, 
            org : fieldmapper.aou.descendantNodeList(contextOrg, true) 
        } 
    );
}

function loadYearSelector() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.org.years.retrieve'],
        {   async : true,
            params : [openils.User.authtoken, {}, {limit_perm : 'VIEW_FUND'}],
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

                // add the new, rolled funds to the cache.  Note that in dry-run 
                // mode, these are ephemeral and no longer exist on the server.
                cachedFunds = cachedFunds.concat(rolloverResponses);

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

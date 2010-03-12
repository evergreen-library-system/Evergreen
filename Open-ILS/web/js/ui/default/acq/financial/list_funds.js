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
dojo.require('openils.acq.Fund');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.ProgressDialog');

var contextOrg;

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var id = this.grid.store.getValue( item, 'id');   
    var fund = openils.acq.Fund.cache[id];
    if(fund && fund.summary()) 
        return fund.summary().combined_balance;
    return 0;
}

function initPage() {

    var connect = function() {
        dojo.connect(contextOrgSelector, 'onChange',
            function() {
                contextOrg = this.attr('value');
                lfGrid.resetStore();
                loadFundGrid(fundFilterYearSelect.attr('value'));
            }
        );
    };

    new openils.User().buildPermOrgSelector(
        'ADMIN_ACQ_FUND', contextOrgSelector, null, connect);

    loadYearSelector();
    loadFundGrid();
}

function loadFundGrid(year) {

    lfGrid.resetStore();
    year = year || new Date().getFullYear().toString();
    lfGrid.dataLoader = function() { loadFundGrid(year); };

    if(contextOrg == null)
        contextOrg = openils.User.user.ws_ou();

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
                fundFilterYearSelect.store = new dojo.data.ItemFileReadStore({data:yearStore});

                // default to this year
                fundFilterYearSelect.setValue(new Date().getFullYear().toString());

                dojo.connect(
                    fundFilterYearSelect, 
                    'onChange', 
                    function() {
                        loadFundGrid(fundFilterYearSelect.attr('value'));
                    }
                );
            }
        }
    );
}

function performRollover(args) {
    progressDialog.show(true, "Processing...");

    var method = 'open-ils.acq.fiscal_rollover';

    if(args.rollover[0] == 'on') {
        method += '.combined';
    } else {
        method += '.propagate';
    }
        
    if(args.dry_run[0] == 'on')
        method += '.dry_run';

    var responses = [];
    fieldmapper.standardRequest(
        ['open-ils.acq', method],
        {
            async : true,

            params : [
                openils.User.authtoken, 
                fundFilterYearSelect.attr('value'),
                contextOrg,
                false, // TODO: checkbox in dialog
            ],

            onresponse : function(r) {
                var resp = openils.Util.readResponse(r);
                responses.push(resp);
            }, 

            oncomplete : function() {
                alert(responses.length);
                progressDialog.hide();
            }
        }
    );
}

openils.Util.addOnLoad(initPage);


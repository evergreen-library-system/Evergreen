dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.widget.AutoGrid');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var contextOrg;

function setup() {
    buildGrid();

    var connect = function() {
        dojo.connect(contextOrgSelector, 'onChange',
            function() {
                contextOrg = this.attr('value');
                rGrid.resetStore();
                buildGrid();
            }
        );
    };

    new openils.User().buildPermOrgSelector(
        'CREATE_PICKLIST', contextOrgSelector, null, connect);
}

function buildGrid() {

    if(contextOrg == null)
        contextOrg = openils.User.user.ws_ou();

    rGrid.loadAll(
        {   order_by : {aur : 'request_date'},
            join : 'au' 
        },
        {
            cancel_reason : null,
            '+au' : {
                home_ou : fieldmapper.aou.descendantNodeList(contextOrg).map(
                    function(item) { return item.id(); })
            }
        }
    );
}

openils.Util.addOnLoad(setup);



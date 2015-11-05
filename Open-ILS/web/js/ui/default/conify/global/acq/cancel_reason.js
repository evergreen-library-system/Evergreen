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
                crGrid.resetStore();
                buildGrid();
            }
        );
    };

    crGrid.disableSelectorForRow = function(rowIdx) {
        var item = crGrid.getItem(rowIdx);
        return (crGrid.store.getValue(item, 'id') < 2000);
    }

    new openils.User().buildPermOrgSelector(
        'ADMIN_ACQ_CANCEL_CAUSE', contextOrgSelector, null, connect);
}

function buildGrid() {

    if(contextOrg == null)
        contextOrg = openils.User.user.ws_ou();

    crGrid.loadAll( 
        {order_by : {acqcr : 'label'}}, 
        {org_unit : fieldmapper.aou.fullPath(contextOrg, true)}
    );
}

openils.Util.addOnLoad(setup);



dojo.require('dijit.layout.ContentPane');
dojo.require("dojo.dnd.Container");
dojo.require("dojo.dnd.Source");
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var user;
var orders;
var locations;
var source;

function init() {

     user = new openils.User();
     source = new dojo.dnd.Source('acl-ol');

     user.buildPermOrgSelector(
        'ADMIN_COPY_LOCATION_ORDER', 
        contextOrgSelector, 
        null, 
        function() {
              dojo.connect(contextOrgSelector, 'onChange', filterGrid);
        }
    );

    filterGrid(user.user.ws_ou());
}

function filterGrid(org) {

    // fetch the locations and order entries
    if(!orders) {
        var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
        orders = pcrud.search('acplo', {org : org}, {order_by : {acplo : 'position'}});
        locations = pcrud.search('acpl', 
            {owning_lib : fieldmapper.aou.orgNodeTrail(fieldmapper.aou.findOrgUnit(org), true)}, 
            {order_by : {acpl : 'name'}}
        ); 
    }

    // init the DnD environment
    source.selectAll();
    source.deleteSelectedNodes();
    source.clearItems();

    var locs = [];

    // sort and append by existing order settings
    dojo.forEach(
        orders,
        function(order) {
            locs = locs.concat(
                locations.filter(
                    function(l) { return l.id() == order.location(); }
                )
            );
        }
    );

    // append any non-sorted locations
    dojo.forEach(locations, 
        function(l) {
            if(!locs.filter(function(ll) { return ll.id() == l.id() })[0])
                locs.push(l);
        }
    );

    // shove them into the DnD environment
    dojo.forEach(locs,
        function(loc) {
            if(!loc) return;
            var node = source.insertNodes(false, [ 
                { 
                    data : loc.name() + ' (' + fieldmapper.aou.findOrgUnit(loc.owning_lib()).shortname()+')',
                    type : [loc.id()+''] // use the type field to store the ID
                }
            ]);
        }
    );
}

function applyChanges() {
    progressDialog.show();

    var newOrders = [];
    var contextOrg = contextOrgSelector.attr('value');

    // pull the locations out of the DnD environment and create order entries for them
    dojo.forEach(
        source.getAllNodes(),
        function(node) {
            var item = source.getItem(node.id);
            var o = new fieldmapper.acplo();
            o.position(newOrders.length + 1);
            o.location(item.type[0]); // location.id() is stored in DnD item type
            o.org(contextOrg);
            newOrders.push(o);
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.copy_location_order.update'],
        {
            async : true,
            params : [openils.User.authtoken, newOrders],
            onresponse : function(r) {
                if(r = openils.Util.readResponse(r)) {
                    if(r.orders) {
                        orders = r.order;
                        progressDialog.hide();
                        filterGrid(contextOrg);
                        return;
                    } 
                    progressDialog.update(r);
                }
            },
        }
    );
}

openils.Util.addOnLoad(init);


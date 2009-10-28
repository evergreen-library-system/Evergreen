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
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    orders = pcrud.search('acplo', {org : org}, {order_by : {acplo : 'position'}});
    locations = pcrud.search('acpl', {owning_lib : org}, {order_by : {acpl : 'name'}}); // TODO

    // init the DnD environment
    source.selectAll();
    source.deleteSelectedNodes();
    source.clearItems();

    var locs = [];

    // sort and append by existing order settings
    dojo.forEach(orders, 
        function(order) {
            locs.push( 
                locations.filter(function(l) {return l.id() == order.location()})[0] 
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
    progressDialog.show(true);
    if(orders.length) 
        deleteOrders(createOrders);
    else
        createOrders();
}

function deleteOrders(onload) {
    // delete the existing order entries in preparation for new ones
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    pcrud.delete(
        orders,
        {
            async : true,
            oncomplete : function() {
                if(onload) onload();
            }
        }
    );
}

function createOrders() {

    var newOrders = [];

    // pull the locations out of the DnD environment and create order entries for them
    dojo.forEach(
        source.getAllNodes(),
        function(node) {
            var item = source.getItem(node.id);
            var o = new fieldmapper.acplo();
            o.position(newOrders.length + 1);
            o.location(item.type[0]); // location.id() is stored in DnD item type
            o.org(contextOrgSelector.attr('value'));
            newOrders.push(o);
        }
    );

    // send the order entries off to the server
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    pcrud.create(
        newOrders,
        {
            async : true,
            oncomplete : function(r) {
                progressDialog.hide();
                filterGrid(contextOrgSelector.attr('value'));
            }
        }
    );
}

openils.Util.addOnLoad(init);


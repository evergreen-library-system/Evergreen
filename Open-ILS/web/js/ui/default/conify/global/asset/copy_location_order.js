dojo.require('dijit.layout.ContentPane');
dojo.require("dojo.dnd.Container");
dojo.require("dojo.dnd.Source");
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.PermaCrud');

var user;
var pcrud;
var orders;
var locations;
var source;

function init() {

     user = new openils.User();
     pcrud = new openils.PermaCrud({authtoken : user.authtoken});
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
    orders = pcrud.search('acplo', {org : org}, {order_by : {acplo : 'position'}});
    locations = pcrud.search('acpl', {owning_lib : org}); //TODO
    source.selectAll();
    source.deleteSelectedNodes();
    source.clearItems();

    dojo.forEach(locations, 
        function(loc) {
            source.insertNodes(false, [
                loc.name() + ' (' + fieldmapper.aou.findOrgUnit(loc.owning_lib()).shortname()+')'
            ]);
        }
    );
}

openils.Util.addOnLoad(init);


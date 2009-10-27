dojo.require('dijit.layout.ContentPane');
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
var tbody;
var template;

function init() {

     user = new openils.User();
     pcrud = new openils.PermaCrud({authtoken : user.authtoken});
     tbody = dojo.byId('acpl-tbody');
     template = tbody.removeChild(dojo.byId('acpl-tr'));
     

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
    alert(locations.length);

    while(tbody.childNodes[0]) 
        tbody.removeChild(tbody.childNodes[0]);

    dojo.forEach(locations, 
        function(loc) {
            var row = template.cloneNode(true);
            dojo.query('[name=name]', row)[0].innerHTML = loc.name();
            dojo.query('[name=owning_lib]', row)[0].innerHTML = 
                fieldmapper.aou.findOrgUnit(loc.owning_lib()).shortname();
            tbody.appendChild(row);
            console.log(row);
        }
    );
}

openils.Util.addOnLoad(init);


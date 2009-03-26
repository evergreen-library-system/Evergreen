dojo.require('dojox.grid.DataGrid');
dojo.require('openils.widget.AutoGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('dijit.Dialog');
dojo.require('dojox.widget.PlaceholderMenuItem');
dojo.require('fieldmapper.OrgUtils');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var btContextOrg;
var btList;

/** really need to put this in a shared location... */
function getOrgInfo(rowIndex, item) {
    if(!item) return '';
    var orgId = this.grid.store.getValue(item, this.field);
    return fieldmapper.aou.findOrgUnit(orgId).shortname();
}

function btInit() {

    buildBTGrid();
    var connect = function() {
        dojo.connect(btContextOrgSelect, 'onChange',
                     function() {
                         btContextOrg = this.getValue();
                         btGrid.resetStore();
                         buildBTGrid();
                     }
                    );
    };
    new openils.User().buildPermOrgSelector('VIEW_BILLING_TYPE', btContextOrgSelect, null, connect);
}

function buildBTGrid() {
    if(btContextOrg == null)
        btContextOrg = openils.User.user.ws_ou();
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.billing_type.ranged.retrieve.all'],
        {   async: true,
            params: [openils.User.authtoken, btContextOrg, fieldmapper.aou.findOrgDepth(btContextOrg)],
            oncomplete: function(r) {
                if(btList = openils.Util.readResponse(r)) {
                    btList = openils.Util.objectSort(btList);
                    dojo.forEach(btList,
                                 function(e) {
                                     btGrid.store.newItem(cbt.toStoreItem(e));
                                 }
                                );
                }
            }
        }
    );
}

openils.Util.addOnLoad(btInit);



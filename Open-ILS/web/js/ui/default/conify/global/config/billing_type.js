dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var btContextOrg;
var btList;

function buildBTGrid() {
    if(btContextOrg == null)
       btContextOrg = openils.User.user.ws_ou();
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.billing_type.ranged.retrieve.all'],
        {   async: true,
            params: [openils.User.authtoken, btContextOrg, fieldmapper.aou.findOrgDepth(btContextOrg)],
            oncomplete: function(r) {
                if(btList = openils.Util.readResponse(r)) {
                    var store = new dojo.data.ItemFileReadStore({data:cbt.toStoreData(btList)});
                    btGrid.setStore(store);
                    btGrid.render();
                }
            }
        }
    );
}

openils.Util.addOnLoad(buildBTGrid);



dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('fieldmapper.OrgUtils');
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
                    var store = new dojo.data.ItemFileReadStore({data:cbt.toStoreData(btList)});
                    btGrid.setStore(store);
                    btGrid.render();
                }
            }
        }
    );
}

function btCreate(args) {
    if(!args.name || args.owner == null) 
        return;
    if(args.default_price == '' || isNaN(args.default_price))
        args.default_price = null;

    var btype = new cbt();
    btype.name(args.name);
    btype.owner(args.owner);
    btype.default_price(args.default_price);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.cbt'],
        {   async: true,
            params: [openils.User.authtoken, btype],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    buildBTGrid();
            }
        }
    );
}

openils.Util.addOnLoad(btInit);



dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('dijit.Dialog');
dojo.require('dojox.widget.PlaceholderMenuItem');
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
    btGridMenu.init({
        grid: btGrid,
        prefix: 'conify.global.config.billing_type.btGridMenu',
        authtoken: openils.User.authtoken
    });

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
                    btList = openils.Util.objectSort(btList);
                    var store = new dojo.data.ItemFileWriteStore({data:cbt.toStoreData(btList)});
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

function btDrawEditDialog() {
    btEditDialog.show();
    var item =  btGrid.selection.getSelected()[0];
    if(!item) {
        btEditDialog.hide();
        return;
    }
    var id = btGrid.store.getValue(item, 'id');
    var name = btGrid.store.getValue(item, 'name');
    var owner = btGrid.store.getValue(item, 'owner');
    var price = btGrid.store.getValue(item, 'default_price');

    dojo.byId('btId').innerHTML = id;
    btName.setValue(name);
    btOwnerLocation.setValue(owner);
    btDefaultPrice.setValue(price);
    new openils.User().buildPermOrgSelector('ADMIN_BILLING_TYPE', btOwnerLocation, owner);

    if (id >= 100){
        btOwnerLocation.setDisabled(false);
        btDefaultPrice.setDisabled(false);

    } else {
        btOwnerLocation.setDisabled(true);
        btDefaultPrice.setDisabled(true);
    }
    
    // add an onclick for the save button that knows which object we are editing
    editSave.domNode.onclick = function() {
        var map = openils.Util.mapList(btList, 'id', true);
        var bt = map[id]; // id comes from the getValue() call above
        saveChanges(bt, item);
    }
}


function saveChanges(bt, item){
    bt.name(btName.getValue());
    bt.owner(btOwnerLocation.getValue());
    bt.default_price(btDefaultPrice.getValue());

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.update.cbt'],
        {   async: true,
            params: [openils.User.authtoken, bt],
            oncomplete: function(r) {

                if(openils.Util.readResponse(r)) {
                    // update succeeded.  put the new values into the grid
                    btGrid.store.setValue(item, 'name', bt.name());
                    btGrid.store.setValue(item, 'default_price', (bt.default_price()));
                    btGrid.store.setValue(item, 'owner', bt.owner());
                    btEditDialog.hide();

                } else {
                    // update failed.  indicate this to the user somehow
                    alert('Update Failed. Reason: ');
                }
            }
        }
    );
}
openils.Util.addOnLoad(btInit);



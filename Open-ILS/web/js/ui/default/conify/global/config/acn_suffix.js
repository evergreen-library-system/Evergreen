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

var thingContextOrg;
var thingList;

/** really need to put this in a shared location... */
function getOrgInfo(rowIndex, item) {
    if(!item) return '';
    var orgId = this.grid.store.getValue(item, this.field);
    return fieldmapper.aou.findOrgUnit(orgId).shortname();
}

function thingInit() {

    thingGrid.disableSelectorForRow = function(rowIdx) {
        var item = thingGrid.getItem(rowIdx);
        return (thingGrid.store.getValue(item, 'id') < 0);
    }

    buildGrid();
    var connect = function() {
        dojo.connect(thingContextOrgSelect, 'onChange',
                     function() {
                         thingContextOrg = this.getValue();
                         thingGrid.resetStore();
                         buildGrid();
                     }
                    );
    };
    // go ahead and let staff see everything
    new openils.User().buildPermOrgSelector('STAFF_LOGIN', thingContextOrgSelect, null, connect);
}

function buildGrid() {
    if(thingContextOrg == null)
        thingContextOrg = openils.User.user.ws_ou();

    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.acns.atomic'],
        {   async: true,
            params: [
                openils.User.authtoken,
                {"owning_lib":fieldmapper.aou.descendantNodeList(thingContextOrg,true)},
                {"order_by":{"acns":"label_sortkey"}}
            ],
            oncomplete: function(r) {
                if(thingList = openils.Util.readResponse(r)) {
                    thingList = openils.Util.objectSort(thingList);
                    dojo.forEach(thingList,
                                 function(e) {
                                     thingGrid.store.newItem(acns.toStoreItem(e));
                                 }
                                );
                }
            }
        }
    );
}

openils.Util.addOnLoad(thingInit);



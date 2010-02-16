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

var alertContextOrg;
var alertList;

function alertInit() {

    buildAlertGrid();
    var connect = function() {
        dojo.connect(alertContextOrgSelect, 'onChange',
                     function() {
                         alertContextOrg = this.getValue();
                         alertGrid.resetStore();
                         buildAlertGrid();
                     }
                    );
    };
    new openils.User().buildPermOrgSelector('ADMIN_ACQ_LINEITEM_ALERT_TEXT', alertContextOrgSelect, null, connect);
}

function buildAlertGrid() {
    if(alertContextOrg == null)
        alertContextOrg = openils.User.user.ws_ou();
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.line_item_alert_text.ranged.retrieve.all'],
        {   async: true,
            params: [openils.User.authtoken, alertContextOrg, fieldmapper.aou.findOrgDepth(alertContextOrg)],
            oncomplete: function(r) {
                if(alertList = openils.Util.readResponse(r)) {
                    alertList = openils.Util.objectSort(alertList);
                    dojo.forEach(alertList,
                                 function(e) {
                                     alertGrid.store.newItem(acqliat.toStoreItem(e));
                                 }
                                );
                }
            }
        }
    );
}

openils.Util.addOnLoad(alertInit);



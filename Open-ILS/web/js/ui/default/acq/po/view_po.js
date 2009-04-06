dojo.require('dijit.layout.ContentPane');
dojo.require('openils.User');
dojo.require('openils.Util');

var PO = null;
var liTable;

function init() {
    liTable = new AcqLiTable();
    liTable.reset();
    liTable.isPO = poId;

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, poId],
            oncomplete: function(r) {
                PO = openils.Util.readResponse(r);
                console.log('got PO');
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [openils.User.authtoken, {purchase_order:poId}, {flesh_attrs:true}],
            onresponse: function(r) {
                liTable.show('list');
                liTable.addLineitem(openils.Util.readResponse(r));
            }
        }
    );
}

openils.Util.addOnLoad(init);

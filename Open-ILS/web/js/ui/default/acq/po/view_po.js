dojo.require('dijit.layout.ContentPane');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');

var PO = null;
var liTable;

function init() {
    liTable = new AcqLiTable();
    liTable.reset();
    liTable.isPO = poId;

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, poId, {flesh_price_summary:true, flesh_lineitem_count:true}],
            oncomplete: function(r) {
                PO = openils.Util.readResponse(r);
                dojo.byId('acq-po-view-id').innerHTML = PO.id();
                dojo.byId('acq-po-view-name').innerHTML = PO.name();
                dojo.byId('acq-po-view-total-li').innerHTML = PO.lineitem_count();
                dojo.byId('acq-po-view-total-enc').innerHTML = PO.amount_encumbered();
                dojo.byId('acq-po-view-total-spent').innerHTML = PO.amount_spent();
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [openils.User.authtoken, {purchase_order:poId}, {flesh_attrs:true, flesh_notes:true}],
            onresponse: function(r) {
                liTable.show('list');
                liTable.addLineitem(openils.Util.readResponse(r));
            }
        }
    );
}

function updatePoName() {
    var value = prompt('Enter new purchase order name:', PO.name()); // TODO i18n
    if(!value || value == PO.name()) return;
    PO.name(value);
    var pcrud = new openils.PermaCrud();
    pcrud.update(PO, {
        oncomplete : function(r) {
            var stat = openils.Util.readResponse(r);
            if(stat) 
                dojo.byId('acq-po-view-name').innerHTML = value;
        }
    });
}

openils.Util.addOnLoad(init);

dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.EditPane');

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var pcrud = new openils.PermaCrud();
var invoice;

function init() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.invoice.retrieve'],
        {
            params : [openils.User.authtoken, invoiceId],
            oncomplete : function(r) {
                invoice = openils.Util.readResponse(r);     
                drawInvoicePane(dojo.byId('acq-view-invoice-div'), invoice);
            }
        }
    );
}

openils.Util.addOnLoad(init);



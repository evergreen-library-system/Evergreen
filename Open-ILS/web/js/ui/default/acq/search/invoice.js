dojo.require('openils.widget.ProgressDialog');

function getInvIdent(rowIndex, item) {
    if (item) {
        return {
            "inv_ident": this.grid.store.getValue(item, "inv_ident") ||
                this.grid.store.getValue(item, "id"),
            "id": this.grid.store.getValue(item, "id")
        };
    }
}

function formatInvIdent(inv) {
    if (inv) {
        return "<a href='" + oilsBasePath + "/acq/invoice/view/" +
            inv.id + "'>" + inv.inv_ident + "</a>";
    }
}

function printInvoiceVouchers() {
    var inv_ids = dijit.byId("acq-unified-inv-grid").
        getSelectedItems().map(function(o) {return o.id[0];});

    progressDialog.show(true);

    var html;
    if (inv_ids.length) {
        var win = null;
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.invoice.print.html"], {
                "params": [openils.User.authtoken, inv_ids],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        if(!html) {
                            html = "<style type='text/css'>.acq-invoice-" +
                                "voucher {page-break-after:always;}" +
                                "</style>\n";
                        }
                        html += r.template_output().data();
                    }
                },
                "oncomplete": function() { 
                    progressDialog.hide();
                    openils.Util.printHtmlString(html);
                }
            }
        );
    }
}

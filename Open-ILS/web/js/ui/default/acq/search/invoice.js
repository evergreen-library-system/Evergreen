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

    /* XXX this business about opening a window and populating its
     * body should be wrapped up in a simple dijit or something.
     * consolidate with claim_voucher.js maybe. */
    if (inv_ids.length) {
        var win = null;
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.invoice.print.html"], {
                "params": [openils.User.authtoken, inv_ids],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        if (!win) {
                            win = window.open(
                                "", "", "resizable,width=800," +
                                "height=600,scrollbars=1"
                            );
                            win.document.title = localeStrings.INVOICES;
                            win.document.body.innerHTML =
                                "<style type='text/css'>.acq-invoice-" +
                                "voucher {page-break-after:always;}" +
                                "</style>\n";
                        }
                        win.document.body.innerHTML +=
                            r.template_output().data();
                    }
                },
                "oncomplete": function() { win.print(); }
            }
        );
    }
}

function InvoiceLinkDialogManager(which, target) {
    var self = this;
    this.inv = null;

    this.linkFoundInvoice = function(r) {
        self.inv = openils.Util.readResponse(r);
        var path = oilsBasePath + "/acq/invoice/view/" + self.inv.id();
        if (!dojo.isArray(self.target)) self.target = [self.target];
        dojo.forEach(self.target, function(target, idx) { 
            id = (typeof target != 'object') ? target : target.id();
            var join = (idx == 0) ? '?' : '&';
            path += join + "attach_" + self.which + "=" + id;
        });
        location.href = path;
    };

    this.which = which;
    if (target)
        this.target = target;

    new openils.widget.AutoFieldWidget({
        "fmField": "provider",
        "fmClass": "acqinv",
        "parentNode": dojo.byId("acq-" + this.which + "-link-invoice-provider"),
        "orgLimitPerms": ["VIEW_INVOICE"],
        "forceSync": true
    }).build();

    dijit.byId("acq-" + this.which + "-link-invoice-link").onClick =
        function() {
            self.inv = null;
            pcrud.search(
                "acqinv", {
                    "provider": dijit.byId(
                            "acq-" + self.which + "-link-invoice-provider"
                        ).attr("value"),
                    "inv_ident":
                        dijit.byId(
                            "acq-" + self.which + "-link-invoice-inv_ident"
                        ).attr("value")
                }, {
                    "async": true,
                    "streaming": true,
                    "onresponse": self.linkFoundInvoice,
                    "oncomplete": function() {
                        if (!self.inv)
                            alert(localeStrings.NO_FIND_INVOICE);
                    }
                }
            );
        };
}

dojo.require("dijit.form.Button");
dojo.require("dijit.form.TextBox");
dojo.require("openils.acq.Lineitem");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.require("openils.widget.ProgressDialog");
dojo.require("openils.widget.AutoFieldWidget");

var eligibleLiTable;

function nodeByName(n, c) { return dojo.query("[name='" + n + "']", c)[0]; }

function EligibleLiTable(filter) {
    var self = this;

    this.filter = filter;
    this.liCache = {};
    this.numClaimableLids = {};

    this.claimNote = dijit.byId("acq-eligible-claim-note");
    this.table = dojo.byId("acq-eligible-li-table");
    this.tBody = dojo.query("tbody", this.table)[0];
    this.tHead = dojo.query("thead", this.table)[0];
    [this.rowTemplate, this.emptyTemplate] =
        dojo.query("tr", this.tBody).map(
            function(o) { return self.tBody.removeChild(o); }
        );

    nodeByName("selector_all", this.tHead).onclick = function() {
        var value = this.checked;
        dojo.query("[name='selector']", self.tBody).forEach(
            function(o) { o.checked = value; }
        );
    };

    new openils.widget.AutoFieldWidget({
        "fmClass": "acqclt",
        "selfReference": true,
        "dijitArgs": {"required": true},
        "parentNode": dojo.byId("acq-eligible-claim-type")
    }).build(function(w) { self.claimType = w; });

    new openils.User().buildPermOrgSelector(
        "VIEW_PURCHASE_ORDER", orderingAgency, null,
        function() {
            orderingAgency.attr("value", self.filter.ordering_agency);
            dojo.connect(
                orderingAgency, "onChange",
                function() {
                    self.filter.ordering_agency = this.attr("value");
                    self.load();
                }
            );
            self.load();
        }
    );

    dojo.byId("acq-eligible-claim-submit").onclick = function() {
        finalClaimDialog.hide();
        self.claim(self.getSelected());
    };

    dojo.query("button[name='claim_submit']").forEach(
        function(button) {
            button.onclick = function() {
                if (self.getSelected().length)
                    finalClaimDialog.show();
                else
                    alert(localeStrings.NO_LI_TO_CLAIM);
            };
        }
    );

    this.showEmpty = function() {
        dojo.place(dojo.clone(this.emptyTemplate), this.tBody, "only");
        openils.Util.hide("acq-eligible-claim-controls");
    };

    this.load = function() {
        progressDialog.show(true);

        var count = 0;
        this.reset();
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.claim.eligible.lineitem_detail.atomic"], {
                "params": [openils.User.authtoken, this.filter],
                "async": true,
                "oncomplete": function(r) {
                    progressDialog.hide();
                    var rset = openils.Util.readResponse(r);
                    if (rset.length < 1) self.showEmpty();
                    else {
                        var byLi = {};
                        rset.forEach(
                            function(r) {
                                byLi[r.lineitem()] =
                                    (byLi[r.lineitem()] || 0) + 1;
                            }
                        );
                        for (var key in byLi)
                            self.addIfMissing(key, byLi[key]);
                    }
                }
            }
        );
    };

    this.reset = function() {
        this.liCache = {};
        this.numClaimableLids = {};
        dojo.empty(this.tBody);
    };

    this._updateLidLink = function(liId) {
        this.numClaimableLids[liId] = (this.numClaimableLids[liId] || 0) + 1;
        if (this.numClaimableLids[liId] == 2) {
            nodeByName("lid_link", "eligible-li-" + liId).onclick =
                function() {
                    location.href = oilsBasePath + "/acq/po/view/" +
                        self.liCache[liId].purchase_order().id() + "/" +
                        liId;
                };
            openils.Util.show(
                nodeByName("lid_link_holder", "eligible-li-" + liId)
            );
        }
    };

    /* Despite being called with an argument that's a lineitem ID, this method
     * is actually called once per lineitem _detail_. */
    this.addIfMissing = function(liId, number_of_appearances) {
        var row = dojo.clone(this.rowTemplate);

        var checkbox = nodeByName("selector", row);
        var desc = nodeByName("description", row);

        openils.acq.Lineitem.fetchAndRender(
            liId, null, function(li, contents) {
                self.liCache[liId] = li;

                desc.innerHTML = contents;
                dojo.attr(row, "id", "eligible-li-" + liId);
                dojo.attr(checkbox, "value", liId);
                dojo.place(row, self.tBody, "last");

                for (var i = 0; i < number_of_appearances; i++)
                    self._updateLidLink(liId);
            }
        );
    };

    /* Despite being called with an argument that's a lineitem ID, this method
     * is actually called once per lineitem _detail_. */
    this.removeIfPresent = function(liId) {
        if (this.liCache[liId]) {
            delete this.liCache[liId];
            delete this.numClaimableLids[liId];
            this.tBody.removeChild(dojo.byId("eligible-li-" + liId));
        }
    };

    this.getSelected = function() {
        return dojo.query("[name='selector']", this.tBody).
            filter(function(o) { return o.checked; }).
            map(function(o) { return o.value; });
    };

    this.resetVoucher = function() { this.voucherWin = null; };

    this.addToVoucher = function(contents) {
        if (!this.voucherWin)
            this.voucherWin = openClaimVoucherWindow();
        dojo.byId("main", this.voucherWin.document).innerHTML +=
            (contents + "<hr />");
    };

    this.finishVoucher = function() {
        var print_btn = dojo.byId("print", this.voucherWin.document);
        print_btn.disabled = false;
        print_btn.innerHTML = localeStrings.PRINT;
    };

    this.claim = function(lineitems) {
        progressDialog.show(true);
        self.resetVoucher();

        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.claim.lineitem"], {
                "params": [
                    openils.User.authtoken, lineitems, null,
                    this.claimType.attr("value"), this.claimNote.attr("value")
                ],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r))
                        self.addToVoucher(r.template_output().data());
                    else
                        progressDialog.hide();
                },
                "oncomplete": function() {
                    lineitems.forEach(
                        function(liId) { self.removeIfPresent(liId); }
                    );
                    if (!nodeByName("selector", self.tBody)) // emptiness test
                        self.showEmpty();

                    self.finishVoucher();
                    progressDialog.hide();
                }
            }
        );
    };
}

function init() {
    var finished_filter = {};
    if (filter && filter.indexOf(":") != -1) {
        filter.split(",").forEach(
            function(chunk) {
                var kvlist = chunk.split(":");
                finished_filter[kvlist[0]] = kvlist[1];
            }
        );
    }
    filter = finished_filter;

    if (!filter.ordering_agency)
        filter.ordering_agency = openils.User.user.ws_ou();

    eligibleLiTable = new EligibleLiTable(filter);
}

openils.Util.addOnLoad(init);

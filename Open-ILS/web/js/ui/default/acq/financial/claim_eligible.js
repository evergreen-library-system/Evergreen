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

    this.showEmpty = function() {
        dojo.place(dojo.clone(this.emptyTemplate), this.tBody, "only");
        openils.Util.hide("acq-eligible-claim-controls");
    };

    this.load = function() {
        progressDialog.show(true);

        var count = 0;
        this.reset();
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.claim.eligible.lineitem_detail"], {
                "params": [openils.User.authtoken, this.filter],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        if (!count++)
                            openils.Util.show("acq-eligible-claim-controls");
                        self.addIfMissing(r.lineitem());
                    } else {
                        progressDialog.hide();
                    }
                },
                "oncomplete": function() {
                    if (count < 1) self.showEmpty();
                    progressDialog.hide();
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
                        self.liCache[liId].purchase_order().id() + "," +
                        liId;
                };
            openils.Util.show(
                nodeByName("lid_link_holder", "eligible-li-" + liId)
            );
        }
    };

    /* Despite being called with an argument that's a lineitem ID, this method
     * is actually called once per lineitem _detail_. */
    this.addIfMissing = function(liId) {
        this._updateLidLink(liId);
        if (this.liCache[liId]) return;

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
        if (!this.voucherWin) {
            this.voucherWin = window.open(
                "", "", "resizable,width=800,height=600,scrollbars=1"
            );
            this.voucherWin.document.title = localeStrings.CLAIM_VOUCHERS;
            this.voucherWin.document.body.innerHTML = (
                "<button onclick='window.print();'>" +
                localeStrings.PRINT +
                "</button><hr /><div id='main'></div>"
            );
        }
        dojo.byId("main", this.voucherWin.document).innerHTML += (
            contents + "<hr />"
        );
    };

    this.claim = function() {
        var lineitems = this.getSelected();
        if (!lineitems.length) {
            alert(localeStrings.NO_LI_TO_CLAIM);
            return;
        }

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
                var [key, value] = chunk.split(":");
                finished_filter[key] = value;
            }
        );
    }
    filter = finished_filter;

    if (!filter.ordering_agency)
        filter.ordering_agency = openils.User.user.ws_ou();

    eligibleLiTable = new EligibleLiTable(filter);
}

openils.Util.addOnLoad(init);

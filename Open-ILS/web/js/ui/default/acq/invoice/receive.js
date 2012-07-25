dojo.require("dijit.form.Button");
dojo.require("dijit.form.NumberSpinner");
dojo.require("openils.PermaCrud");
dojo.require("openils.acq.Lineitem");
dojo.require("openils.widget.AutoFieldWidget");
dojo.require("openils.widget.ProgressDialog");
dojo.requireLocalization("openils.acq", "acq");

var copy_table;
var localeStrings = dojo.i18n.getLocalization("openils.acq", "acq");

function ReceivableCopyTable() {
    var self = this;

    this._init = function() {
        this.columns = ["owning_lib", "location", "collection_code",
            "circ_modifier", "fund", "cn_label", "barcode"];

        this.tbody = dojo.byId("rows-here");
        this.pcrud = new openils.PermaCrud();

        this.mode = "number";   /* can be "number" or "list" */
        this.some_receiving_done = false;

        this._init_select_all();
    };

    this._init_select_all = function() {
        dojo.byId("select_all").onchange = function() {
            var checked = this.checked;
            dojo.query("input[type='checkbox']", self.tbody).forEach(
                function(cb) { cb.checked = checked; }
            );
        };
    };

    this._set_invoice_header = function() {
        dojo.byId("inv-header").innerHTML = dojo.string.substitute(
            localeStrings.INVOICE_NUMBER, [this.invoice.inv_ident()]
        );
    };

    this._configure_for_mode = function() {
        if (this.mode == "list") {
            openils.Util.show("list-mode-headings", "table-header-group");
            openils.Util.hide("set-list-mode");
            openils.Util.show("set-number-mode");
            dojo.byId("set-number-mode-link").onclick = function() {
                self.reset("number");
                self.load();
            };
        } else { /* number */
            openils.Util.hide("list-mode-headings");
            openils.Util.show("set-list-mode");
            openils.Util.hide("set-number-mode");
            dojo.byId("set-list-mode-link").onclick = function() {
                self.reset("list");
                self.load();
            };
        }
    };

    this._get_receivable_details = function(li) {
        return li.lineitem_details().filter(
            function(lid) { return (!lid.recv_time() && !lid.cancel_reason()); }
        );
    };

    this._create_receiver = function(lid, tr, precheck) {
        var args = {
            "type": "checkbox",
            "name": "receive",
            "value": lid.id()
        };

        if (precheck) args.checked = "checked";

        dojo.create("input", args, dojo.create("td", null, tr));
    };

    this._get_selected_list_mode = function() {
        return dojo.query("input[type=checkbox]", this.tbody).filter(
            function(cb) { return cb.checked; }
        ).map(
            function(cb) { return cb.value; }
        );
    };

    this._get_selected_number_mode = function() {
        var list = [];
        for (var li_id in this.spinners) {
            var spinner = this.spinners[li_id];
            var li = spinner._li;

            var number = spinner.attr("value");
            list = list.concat(
                this._get_receivable_details(li).slice(0, number)
            );
        }
        return list.map(function(lid) { return lid.id(); });
    };

    /* The first time this interface is loaded, use the phys_item_count field
     * (the "# paid" column on an invoice) to determing how man items to
     * preselect.  Otherwise use 0.
     */
    this._number_to_preselect = function(ie, li) {
        return (this.some_receiving_done) ? 0 :
            Number(ie.phys_item_count() || 0);

//        var n = Number(ie.phys_item_count() || 0) -
//            li.lineitem_details().filter(
//                function(lid) {
//                    return lid.recv_time() || lid.cancel_reason()
//                }
//            ).length;
//
//        return n > 0 ? n : 0;
    };

    this._render_copy_count_info = function() {
        dojo.byId("inv-copy-count-info").innerHTML =
            dojo.string.substitute(
                localeStrings.INVOICE_COPY_COUNT_INFO,
                [this.copy_number_received, this.copy_number_total]
            );
    };

    this._increment_copy_count_info = function(li) {
        var all_uncanceled = li.lineitem_details().filter(
            function(lid) { return !lid.cancel_reason(); }
        );
        this.copy_number_total += all_uncanceled.length;
        this.copy_number_received += all_uncanceled.filter(
            function(lid) { return Boolean(lid.recv_time()); }
        ).length;
    };

    this._add_lineitem_number_mode = function(details, li, preselect_count) {
        var tr = dojo.create("tr", null, this.tbody);
        var td = dojo.create("td", {
            "colspan": 1 + this.columns.length,
            "className": "spinner-cell"
        }, tr);

        var span_id = "number-mode-li-" + li.id();

        td.innerHTML = localeStrings.COPIES_TO_RECEIVE;
        dojo.create("span", {"id": span_id}, td);

        var max = details.length;
        var value = (preselect_count <= max ? preselect_count : max);

        this.spinners[li.id()] = new dijit.form.NumberSpinner({
            "constraints": {"min": 0, "max": max},
            "value": value
        }, span_id);
        this.spinners[li.id()]._li = li;
    };

    this._add_lineitem_list_mode = function(details, li, preselect_count) {
        details.forEach(
            function(lid) {
                //dump("preselect_count "+ preselect_count+"\n");
                self.add_lineitem_detail(
                    lid, li, Boolean(preselect_count-- > 0)
                );
            }
        );
    };

    this.add_lineitem_detail = function(lid, li, precheck) {
        var tr = dojo.create(
            "tr", {"className": "copy-row"}, this.tbody
        );

        /* Make receive checkbox cell. */
        this._create_receiver(lid, tr, precheck);

        /* Make cells for all the other columns.  Using a read-only
         * AutoFieldWidget to show the value of each field on a lineitem
         * detail is much easier than worrying about fleshing enough
         * information to do the same ourselves. */
        this.columns.forEach(
            function(column) {
                var td = dojo.create("td", null, tr);
                new openils.widget.AutoFieldWidget({
                    "parentNode": dojo.create("div", null, td),
                    "fmField": column,
                    "fmObject": lid,
                    "readOnly": true,
                    "dijitArgs": {"labelType": (column=='fund') ? "html" : null}
                }).build();
            }
        );
    };

    /* /maybe/ add a lineitem to the table, if it has any lineitem details
     * that are still receivable, and preselect lineitem details up to the
     * number specified in ie.phys_item_count() */
    this.add_lineitem = function(ie, li, displayHTML) {
        /* This call only affects the blurb about received vs. total copies
         * on the invoice near the top of the display. */
        this._increment_copy_count_info(li);

        var receivable_details = this._get_receivable_details(li);
        if (!receivable_details.length) return;

        /* show lineitem overall description */
        /* add rows for copies (lineitem details) */
        dojo.create(
            "td", {
                "colspan": 1 + this.columns.length,
                "innerHTML": displayHTML
            }, dojo.create("tr", null, this.tbody)
        );

        /* build look-up table */
        receivable_details.forEach(
            function(lid) { self.li_by_lid[lid.id()] = li; }
        );

        /* Render something for receiving the lineitem details, depending
         * on mode. */
        this["_add_lineitem_" + this.mode + "_mode"](
            receivable_details, li, this._number_to_preselect(ie, li)
        );
    };

    this.reset = function(mode) {
        if (mode)
            this.mode = mode;

        this.user_has_acked = [];
        this.li_by_lid = {};
        this.copy_number_received = 0;
        this.copy_number_total = 0;

        if (this.spinners) {
            for (var key in this.spinners)
                this.spinners[key].destroy();
        }

        this.spinners = {};

        this._configure_for_mode();

        dojo.empty(this.tbody);
    };

    /* It's important to remember that an invoice doesn't actually have
     * lineitems, but rather is made up of invoice entries and invoice items.
     * Invoice entries usually link to lineitems, though (invoice items
     * usually link to po_items).
     */
    this.load = function(inv_id) {
        if (inv_id)
            this.inv_id = inv_id;

        this.reset();
        progress_dialog.show(true);

        if (!this.invoice) {
            this.invoice = this.pcrud.retrieve("acqinv", this.inv_id);
            this._set_invoice_header();
        }

        this.pcrud.search("acqie", {"invoice": this.inv_id}).forEach(
            function(entry) {
                if (entry.lineitem()) {
                    openils.acq.Lineitem.fetchAndRender(
                        entry.lineitem(),
                        {"flesh_li_details": true, "flesh_notes": true},
                        function(li, str) { self.add_lineitem(entry, li, str); }
                    );
                }
            }
        );

        this._render_copy_count_info();

        if (openils.Util.objectProperties(this.li_by_lid).length) {
            openils.Util.show("non-empty");
            openils.Util.hide("empty");
        } else {
            openils.Util.hide("non-empty");
            openils.Util.show("empty");
        }
        progress_dialog.hide();
    };

    /* returns an array of lineitem_detail IDs */
    this.get_selected = function() {
        return this["_get_selected_" + this.mode + "_mode"]();
    };

    this.receive_lineitem_detail = function(id_list, index) {
        if (index >= id_list.length) {
            progress_dialog.hide();
            this.load();

            return;
        }

        var lid_id = id_list[index];
        var li = this.li_by_lid[lid_id];

        if (!this.check_lineitem_alerts(li)) {
            self.receive_lineitem_detail(id_list, ++index);
            return;
        }

        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.lineitem_detail.receive"], {
                "async": false,
                "params": [openils.User.authtoken, lid_id],
                "oncomplete": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        self.some_receiving_done = true;
                        /* receive the next lid in our list */
                        self.receive_lineitem_detail(id_list, ++index);
                    }
                }
            }
        );
    };

    this.receive_selected = function() {
        var lid_ids = this.get_selected();

        progress_dialog.show(true);

        this.receive_lineitem_detail(lid_ids, 0);
    };

    /* 1st of 2 functions all but copied from li_table.js. Refactor this and
     * that to share code from a 3rd place.
     */
    this.check_lineitem_alerts = function(lineitem) {
        var alert_notes = lineitem.lineitem_notes().filter(
            function(o) { return Boolean(o.alert_text()); }
        );

        var i, note, n_notes = alert_notes.length;
        for (i = 0; i < n_notes; i++) {
            note = alert_notes[i];
            if (this.user_has_acked[note.id()])
                continue;
            else if (!this.confirm_alert(lineitem, note))
                return false;
            else
                this.user_has_acked[note.id()] = true;
        }

        return true;
    };

    /* 2nd of 2 functions all but copied from li_table.js. Refactor this and
     * that to share code from a 3rd place.
     */
    this.confirm_alert = function(lineitem, note) {
        return confirm(
            dojo.string.substitute(
                localeStrings.CONFIRM_LI_ALERT, [
                    (new openils.acq.Lineitem({"lineitem": lineitem})).findAttr(
                        "title", "lineitem_marc_attr_definition"
                    ),
                    note.alert_text().code(),
                    note.alert_text().description() || "",
                    note.value()
                ]
            )
        );
    };

    this.back_to_invoice = function() {
        location.href = oilsBasePath + "/acq/invoice/view/" + this.inv_id;
    };

    this._init.apply(this, arguments);
}

function my_init() {
    copy_table = new ReceivableCopyTable();
    copy_table.load(inv_id);
}

openils.Util.addOnLoad(my_init);

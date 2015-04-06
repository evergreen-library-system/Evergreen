function PoItemTable() {
    var self = this;

    this.init = function(po, pcrud) {
        this.po = po;
        this.pcrud = pcrud || new openils.PermaCrud();

        this.tHead = dojo.byId("acq-po-item-table-headings");
        this.tBody = dojo.byId("acq-po-item-table-items");
        this.template = this.tBody.removeChild(dojo.query("tr", this.tBody)[0]);
        dojo.byId("acq-po-item-table-new-charge").onclick = function() {
            self.addItem();
        };
        dojo.byId("acq-po-item-table-save-new").onclick = function() {
            self.saveNew();
        };

        this.fundAWArgs = {
            "searchFilter": {"active": "t"},
            "searchFormat": ["${0} (${1})", "code", "year"],
            "labelFormat": [
                "<span class='fund_${0}'>${1} (${2})</span>",
                "id", "code", "year"
            ],
            "dijitArgs": {"labelType": "html"},
            "noCache": true
        };

        // limit funds fetched to those the user can use
        new openils.User().getPermOrgList(
            ['CREATE_PURCHASE_ORDER', 'MANAGE_FUND'],
            function(orgs) { self.fundAWArgs.searchFilter.org = orgs },
            true, true // descendants, id_list
        );

        this.reset();
    };

    this.empty = function(which) {
        if (this._empty == which) return; /* nothing to do */

        openils.Util[which ? "show" : "hide"]("acq-po-item-table-i-am-empty");
        openils.Util[which ? "hide" : "show"](this.tHead, "table-header-group");
        this._empty = which;
    };

    this.reset = function() {
        this.rowId = -1;
        this.rows = {};
        this.realItems = {};
        dojo.empty(this.tBody);
        this.empty(true);

        this.disableSave();
    };

    this.hide = function() { openils.Util.hide("acq-po-item-table"); };

    this.show = function() { openils.Util.show("acq-po-item-table"); };

    this.disableSave = function() {
        dojo.byId("acq-po-item-table-save-new").disabled = true;
    };

    this.rowIndices = function() {
        return openils.Util.objectProperties(this.rows);
    };

    this.newRowIndices = function() {
        return this.rowIndices().filter(function(o) { return o < 0; });
    };

    this.saveNew = function() {
        var virtIds = this.newRowIndices();
        var po_items = virtIds.map(
            function(k) {
                var widgets = self.rows[k];
                var po_item = new acqpoi();
                for (var field in widgets)
                    po_item[field](widgets[field].attr("value"));
                po_item.purchase_order(self.po.id());
                return po_item;
            }
        );

        progressDialog.show(true);

        pcrud.create(
            po_items, {
                "oncomplete": function(r, objs) {
                    progressDialog.hide();
                    r = openils.Util.readResponse(r); /* may not use */

                    virtIds.forEach(function(k) { self.deleteRow(k); });
                    objs.forEach(function(o) { self.addItem(o); });
                    refreshPOSummaryAmounts();
                }
            }
        );
    };

    this._deleteRow = function(id) {
        dojo.destroy(dojo.query("[rowId='" + id + "']")[0]);
        delete this.rows[id];
        delete this.realItems[id];

        if (!this.rowIndices().length) this.reset();
        else if (!this.newRowIndices().length) this.disableSave();
    };

    this.deleteRow = function(id) {
        if (id > 0) {
            progressDialog.show(true);
            fieldmapper.standardRequest(
                ['open-ils.acq', 'open-ils.acq.po_item.delete'],
                {   async : true,
                    params: [openils.User.authtoken, id],
                    oncomplete : function(r) {
                        progressDialog.hide();
                        r = openils.Util.readResponse(r); /* may not use */
                        if (r == '1') {
                            refreshPOSummaryAmounts();
                            self._deleteRow(id);
                        } 
                    }
                }
            );
        } else {
            this._deleteRow(id);
        }
    };

    this._addItemRow = function(item) {
        var ourId = item ? item.id() : this.rowId--;

        if (item)
            this.realItems[ourId] = item;

        this.rows[ourId] = {};
        var row = dojo.clone(this.template);
        dojo.attr(row, "rowId", ourId);

        nodeByName("delete", row).onclick = function() {
            self.deleteRow(ourId);
        };

        return {"id": ourId, "node": row};
    };

    /* add a row with widgets for the user to enter new data */
    this.addItem = function(item) {
        var row = this._addItemRow(item);

        dojo.query("td[name]", row.node).forEach(
            function(element) {
                var field = dojo.attr(element, "name");
                var em = dojo.attr(element, "em");
                var awArgs = dojo.mixin(
                    {
                        "fmField": field,
                        "parentNode": dojo.create(
                            "div", {"style": "width: " +
                                String(Number(em) + 1) + "em"},
                            element, "only"
                        ),
                        "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
                        "dijitArgs": {"style": "width: " + em + "em"},
                        "readOnly": Boolean(item)
                    },
                    (field == "fund" ? self.fundAWArgs : {}),
                    (item ? {"fmObject": item} : {"fmClass": "acqpoi"})
                );
                new openils.widget.AutoFieldWidget(awArgs).build(
                    function(w) { self.rows[row.id][field] = w; }
                );
            }
        );

        this.empty(false);

        dojo.place(row.node, this.tBody, "last");
        if (!item)
            dojo.byId("acq-po-item-table-save-new").disabled = false;
    };

    this.init.apply(this, arguments);
}

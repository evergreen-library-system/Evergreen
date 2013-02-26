dojo.require('dijit.form.Form');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');

var metaPO;
var _last_fields;
var general_po_search_opts = {"order_by": {"acqpo": "edit_time DESC"}};

function getPOOwner(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, 'owner');
    return new openils.User({id:data}).user.usrname();
}

function doSearch(fields) {
    _last_fields = dojo.clone(fields); /* Save for re-use */
    var metapo_view = false;

    /* Remove the metapo_view field from 'fields'... we'll use it later */
    if (fields.metapo_view && fields.metapo_view[0]) {
        metapo_view = true;
        delete fields.metapo_view;
    }

    if (
        !(fields.id && fields.id.constructor.name == 'Array') && 
        isNaN(fields.id)
    ) {
        delete fields.id;
        for(var k in fields) {
            if(fields[k] == '' || fields[k] == null)
                delete fields[k];
        }
    } else {
        // ID search trumps other searches
        fields = {id:fields.id};
    }

    // no search fields
    var some = false;
    for(var k in fields) some = true;
    if(!some) fields.id = {'!=' : null};


    if (metapo_view) {
        openils.Util.hide("holds_po_grid");
        loadMetaPO(fields);
    } else {
        if (metaPO) metaPO.myHide();
        openils.Util.show("holds_po_grid");
        poGrid.resetStore();
        poGrid.loadAll(general_po_search_opts, fields);
    }
}

function loadForm() {

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo', 
        fmField : 'provider', 
        parentNode : dojo.byId('po-search-provider-selector'),
        orgLimitPerms : ['VIEW_PURCHASE_ORDER'],
        dijitArgs : {name:'provider', required:false}
    }).build();

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo', 
        fmField : 'ordering_agency', 
        parentNode : dojo.byId('po-search-agency-selector'),
        orgLimitPerms : ['VIEW_PURCHASE_ORDER'],
        dijitArgs : {name:'ordering_agency', required:false}
    }).build();

    if (poIds && poIds.length > 0) {
        dijit.byId("metapo_view").attr("checked", true);
        doSearch({"id": poIds, "metapo_view": [true] /* [sic] */});
    } else {
        doSearch({"ordering_agency": openils.User.user.ws_ou()});
    }
}

function loadMetaPO(fields) {
    var pcrud = new openils.PermaCrud();
    var po_list = pcrud.search("acqpo", fields, general_po_search_opts);
    if (!po_list || !po_list.length) {
        alert(localeStrings.NO_PO_RESULTS);
    } else {
        if (!metaPO) {
            metaPO = new AcqLiTable();
            metaPo.enableActionsDropdownOptions("po");

            /* We need to know the width (in cells) of the template row for
             * the LI table, and we don't want to hardcode it here. */
            metaPO.n_cells = dojo.query("> td", metaPO.rowTemplate).length;

            metaPO._copy_count_cb = function(liId, count) {
                var poId = this.liCache[liId].purchase_order();

                if (this.copy_counts[poId] == undefined)
                    this.copy_counts[poId] = {};
                this.copy_counts[poId][liId] = count;

                this.renderCopyCounts(poId);
                this.renderSummary("copies");
            };
            metaPO.myHide = function() {
                this.hide();
                openils.Util.hide("oils-acq-holds-metapo-summary");
            };
            metaPO.renderSummary = function(part) {
                var self = this;
                /* The idea here will be that if "part" is defined, we'll
                 * just update that part of the metaPO summary, otherwise,
                 * the whole thing. */
                if (part != undefined) {
                    var target = dojo.byId("oils-acq-metapo-summary-" + part);
                    switch (part) {
                        case "copies":
                            target.innerHTML = self.copiesTotal();
                            break;
                        case "po":
                            target.innerHTML = self.working_po_list.length;
                            break;
                        /* Any numeric fields should be named here. */
                        case "amount_encumbered":
                        case "amount_spent":
                            target.innerHTML = self.numericFieldTotal(part);
                            break;
                        default:
                            /* assume a field on the acqpo's themselves */
                            target.innerHTML = self.anyFieldTotal(part);
                            break;
                    }
                } else {
                    openils.Util.show("oils-acq-holds-metapo-summary");
                    self.totalable_fields.forEach(
                        function(f) { self.renderSummary(f); }
                    );
                }
            };
            metaPO.numericFieldTotal = function(field) {
                var self = this;
                var pennies = self.working_po_list.reduce(
                    /* working_po_list contains unfleshed acqpo's, so we must
                     * find the same PO in the poCache */
                    function(p, c) {
                        c = self.poCache[c.id()][field]();
                        return p + Number(c) * 100;
                    }, 0
                );
                return pennies / 100;
            };
            metaPO.anyFieldTotal = function(field) {
                var self = this;
                return self.working_po_list.reduce(
                    /* working_po_list contains unfleshed acqpo's, so we must
                     * find the same PO in the poCache */
                    function(p, c) {
                        c = self.poCache[c.id()][field]();
                        return p + Number(c);
                    }, 0
                );
            };
            metaPO.renderCopyCounts = function(poId) {
                try {
                    dojo.query("td#oils-acq-po-heading-" + poId +
                        ' span span[attr="copies"]')[0].innerHTML =
                            this.copiesByPOId(poId);
                } catch (E) {
                    ;
                }
            };
            metaPO.sectionHeadingById = function(id) {
                var headings = dojo.query("#po-heading-" + id, this.tbody);
                if (headings.length != 1) {
                    alert(localeStrings.PO_HEADING_ERROR);
                    return undefined;
                } else {
                    return headings[0];
                }
            };
            metaPO.sectionHeadingByPOId = function(poId) {
                return this.sectionHeadingById(this.sections_by_poid[poId]);
            };
            metaPO.addSection = function(po) {
                var s = this.sections_by_poid[po.id()] = this.sections++;

                this.tbody.appendChild(
                    dojo.create("tr", {
                        "class": "acq-lit-po-heading", "id": "po-heading-" + s
                    })
                );

                return s;
            };
            metaPO.addLineitemToSection = function(li, section) {
                dojo.place(
                    this.addLineitem(li, true /* skip_final_placement */),
                    this.sectionHeadingById(section),
                    "after"
                );
            };
            metaPO.generateActivator = function(id) {
                return function() {
                    progressDialog.show(true);
                    try {
                        fieldmapper.standardRequest(
                            ["open-ils.acq",
                                "open-ils.acq.purchase_order.activate"], {
                                "async": true,
                                "params": [openils.User.authtoken, id],
                                "oncomplete": function() {
                                    progressDialog.hide();
                                    doSearch(_last_fields);
                                }
                            }
                        );
                    } catch (E) {
                        progressDialog.hide();
                        alert(E); /* XXX */
                    }
                };
            };
            metaPO.renderHeading = function(poId) {
                var self = this;
                var td = dojo.create("td", {"colspan": self.n_cells});
                td.id = "oils-acq-po-heading-" + poId;

                /* Build our HTML structure from the template... */
                dojo.query("> span", "oils-acq-po-heading-template").forEach(
                    function(s) { td.appendChild(s.cloneNode(true)); }
                );

                /* Some fields straight from the PO object... */
                self.po_fields_for_display.forEach(
                    function(f) {
                        dojo.query('[attr="' + f + '"]', td)[0].innerHTML =
                            self.poCache[poId][f]();
                    }
                );

                /* The name field needs special treatment: it's a link */
                dojo.attr(
                    dojo.query('a[attr="name"]', td)[0],
                    "href",
                    oilsBasePath + '/acq/po/view/' + poId
                );

                /* Show an "activate" link, or not, based on "state"... */
                var a = dojo.query('a[attr="activator"]', td)[0];
                if (self.poCache[poId].state() == "pending") {
                    a.onclick = self.generateActivator(poId);
                    openils.Util.show(a, "inline");
                } else {
                    openils.Util.hide(a);
                }

                /* Put the new heading cell in place... */
                dojo.place(td, self.sectionHeadingByPOId(poId), "only");

                /* And finally, render copy info (must happen _after_ heading
                 * is attached to the DOM tree */
                this.renderCopyCounts(poId);
            };
            metaPO.copiesByPOId = function(poId) {
                if (!this.copy_counts[poId]) return undefined;
                var total = 0;
                for (var liId in this.copy_counts[poId]) {
                    total += this.copy_counts[poId][liId];
                }
                return total;
            };
            metaPO.copiesTotal = function() {
                var total = 0;
                for (var poId in this.copy_counts)
                    total += this.copiesByPOId(poId);
                return total;
            };
            metaPO.myReset = function() {
                this.isMeta = true;
                this.sections = 0;
                this.sections_by_poid = {};
                this.copy_counts = {};
                this.po_fields_for_display = [
                    "name", "lineitem_count", "amount_encumbered",
                    "amount_spent", "state"
                ];
                this.totalable_fields = [
                    "po", "lineitem_count", "copies",
                    "amount_encumbered", "amount_spent"
                ];
                openils.Util.hide("oils-acq-holds-metapo-summary");
            };
            metaPO.populate = function(list) {
                var self = this;
                var done = 0;

                self.working_po_list = [];

                progressDialog.show(true);
                list.forEach(function(po) {
                    var sec = self.addSection(po);
                    fieldmapper.standardRequest(
                        ["open-ils.acq", "open-ils.acq.lineitem.search"], {
                            "async": true,
                            "params": [
                                openils.User.authtoken,
                                {"purchase_order": po.id()},
                                {"flesh_attrs": true, "flesh_notes": true}
                            ],
                            "onresponse": function(r) {
                                var li = openils.Util.readResponse(r);
                                if (li) /* sometimes empty string: disregard */
                                    self.addLineitemToSection(li, sec);
                            },
                            "oncomplete": function(r) {
                                self.working_po_list.push(po);
                                self.renderHeading(po.id());
                                self.renderSummary();
                                /* This mechanism avoids calling .show() too
                                 * often or before results are ready, and
                                 * thus smooths out DOM rendering glitches. */
                                if (++done >= list.length) {
                                    done = -1;
                                    self.show("list");
                                    progressDialog.hide();
                                }
                            }
                        }
                    );
                });
                /* This mechanism sees to it that we call .show() at least once
                 * even if the search result population seems to be timing
                 * out or failing. */
                setTimeout(
                    function() {
                        if (done != -1) {
                            self.show("list");
                            progressDialog.hide();
                        }
                    }, 10000    /* 10 seconds: make this configurable? */
                );
            };
        }

        metaPO.reset();
        metaPO.myReset();
        metaPO.populate(po_list);
    }
}

openils.Util.addOnLoad(loadForm);

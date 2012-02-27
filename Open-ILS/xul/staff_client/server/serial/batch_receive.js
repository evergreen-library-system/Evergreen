/* The code in this file relies on common.js */

dojo.require("dojo.cookie");
dojo.require("openils.Util");
dojo.require("openils.User");
dojo.require("openils.CGI");
dojo.require("openils.XUL");
dojo.require("openils.PermaCrud");

var batch_receiver;

function S(k) {
    return dojo.byId("serialStrings").getString("batch_receive." + k).
        replace("\\n", "\n");
}

function F(k, args) {
    return dojo.byId("serialStrings").
        getFormattedString("batch_receive." + k, args).replace("\\n", "\n");
}

function BatchReceiver() {
    var self = this;

    this.init = function(authtoken, bib_id, sub_id) {
        if (authtoken) {
            this.user = new openils.User({"authtoken": authtoken});
            this.pcrud = new openils.PermaCrud({"authtoken": authtoken});
            this.authtoken = authtoken;
        }

        hide("batch_receive_sub");
        hide("batch_receive_entry");
        hide("batch_receive_bibdata_bits");
        hide("batch_receive_sub_bits");
        hide("batch_receive_issuance_bits");
        hide("batch_receive_issuance");

        dojo.byId("bib_lookup_submit").disabled = false;
        dojo.byId("bib_search_term").value = "";

        if (!bib_id) {
            show("batch_receive_bib");
            dojo.byId("bib_search_term").focus();
        }

        if (!this.entry_tbody) {
            this.entry_tbody = dojo.byId("entry_tbody");
            this.template = this.entry_tbody.removeChild(
                dojo.byId("entry_template")
            );
        }

        this._clear_entry_batch_row();

        this._call_number_cache = null;
        this._prepared_call_number_controls = {};
        this._location_by_lib = {};
        this._copy_template_cache = {};
        this._wants_print_routing = {};

        /* empty the entry receiving table if we're starting over */
        if (this.item_cache) {
            for (var id in this.item_cache) {
                this.finish_receipt(this.item_cache[id]);
                hard_empty(this.entry_tbody);
            }
            /* XXX incredibly, running hard_empty() more than once seems to be
             * good and necessary.  There's a bug under the covers somewhere,
             * but this keeps it out of sight for the moment. */
             hard_empty(this.entry_tbody);
        }
        hard_empty(this.entry_tbody);

        this.rows = {};
        this.item_cache = {};

        if (bib_id)
            this.bib_lookup(bib_id, null, true, sub_id);

        busy(false);
    };

    this._clear_entry_batch_row = function() {
        dojo.forEach(
            dojo.byId("entry_batch_row").childNodes,
            function(node) {
                if (node.nodeType == 1 &&
                    node.getAttribute("name") != "barcode")
                    hard_empty(node);
            }
        );
    };

    this._show_bibdata_bits = function() {
        hard_empty("title_here");
        dojo.byId("title_here").appendChild(T(this.bibdata.mvr.title()));
        hard_empty("author_here");

        if (this.bibdata.mvr.author()) {
            dojo.byId("author_here").appendChild(T(this.bibdata.mvr.author()));
            show("author_here_holder");
        } else {
            hide("author_here_holder");
        }

        show("batch_receive_bibdata_bits");
    };

    this._sub_label = function(sub) {
        /* XXX use a formatting string from serial.properties */
        return sub.id() + ": (" + sub.owning_lib().shortname() + ") " +
            D(sub.start_date()) + " - " + D(sub.end_date());
    };

    this._show_sub_bits = function() {
        hard_empty("sublabel_here");
        dojo.place(
            T(this._sub_label(this.sub)),
            "sublabel_here",
            "only"
        );
        hide("batch_receive_sub");
        show("batch_receive_sub_bits");
    };

    this._show_issuance_bits = function() {
        hide("batch_receive_issuance");
        hard_empty("issuance_label_here");
        dojo.place(
            T(this.issuance.label()),
            "issuance_label_here",
            "only"
        );
        show("batch_receive_issuance_bits");
    }

    this._get_receivable_issuances = function() {
        var issuances = [];

        busy(true);
        try {
            fieldmapper.standardRequest(
                ["open-ils.serial", "open-ils.serial.issuances.receivable"], {
                    "params": [this.authtoken, this.sub.id()],
                    "async": false,
                    "onresponse": function(r) {
                        if (r = openils.Util.readResponse(r))
                            issuances.push(r);
                    }
                }
            );
        } catch (E) {
            alert(E);
        }
        busy(false);

        return issuances;
    };

    this._build_circ_modifier_dropdown = function() {
        if (!this._built_circ_modifier_dropdown) {
            var menulist = dojo.create("menulist");
            var menupopup = dojo.create("menupopup", null, menulist, "only");
            dojo.create(
                "menuitem", {"value": 0, "label": S("none")},
                menupopup, "first"
            );

            var mods = [];
            fieldmapper.standardRequest(
                ["open-ils.circ", "open-ils.circ.circ_modifier.retrieve.all"],{
                    "params": [{"full": true}],
                    "async": false,
                    "onresponse": function(r) {
                        if (mods = openils.Util.readResponse(r)) {
                            mods.sort(
                                function(a,b) {
                                    return a.code() > b.code() ? 1 :
                                        b.code() > a.code() ? -1 :
                                        0;
                                }
                            ).forEach(
                                function(mod) {
                                    dojo.create(
                                        "menuitem", {
                                            "value": mod.code(),
                                            "label": document.getElementById('commonStrings').getFormattedString('staff.circ_modifier.display',[mod.code(),mod.name(),mod.description()]) 
                                        }, menupopup, "last"
                                    );
                                }
                            );
                        }
                    }
                }
            );
            if (!mods.length) {
                /* in this case, discard menulist and menupopup */
                this._built_circ_modifier_dropdown =
                    dojo.create("description", {"value": "-"});
            } else {
                this._built_circ_modifier_dropdown = menulist;
            }
        }

        return dojo.clone(this._built_circ_modifier_dropdown);
    };

    this._extend_circ_modifier_for_batch = function(control) {
        dojo.create(
            "menuitem", {"value": -1, "label": "---"},
            dojo.query("menupopup", control)[0],
            "first"
        );
        control.value = -1;
        return control;
    };

    this._build_location_dropdown = function(locs, add_unset_value) {
        var menulist = dojo.create("menulist");
        var menupopup = dojo.create("menupopup", null, menulist, "only");

        if (add_unset_value) {
            dojo.create(
                "menuitem", {"value": -1, "label": "---"}, menupopup, "first"
            );
        }

        locs.forEach(
            function(loc) {
                dojo.create(
                    "menuitem", {
                        "value": loc.id(), "label": loc.name()
                    }, menupopup, "last"
                );
            }
        );

        return menulist;
    };

    this._get_locations_for_lib = function(lib) {
        if (!this._location_by_lib[lib]) {
            fieldmapper.standardRequest(
                ["open-ils.circ", "open-ils.circ.copy_location.retrieve.all"],{
                    "params": [lib, false, true],
                    "async": false,
                    "onresponse": function(r) {
                        if (locs = openils.Util.readResponse(r))
                            self._location_by_lib[lib] = locs;
                    }
                }
            );
        }

        return this._location_by_lib[lib];
    };

    this._build_call_number_control = function(item) {
        /* In any case, give a dropdown of call numbers related to the
         * same bre as the subscription relates to. */
        if (!this._call_number_cache) {
            this._call_number_cache = this.pcrud.search(
                "acn", {
                    "record": this.sub.record_entry()
                }, {
                    "order_by": {"acn": "label"},   /* XXX wrong sorting? */
                }
            );
        }

        if (typeof item == "undefined") {
            /* In this case, no further limiting of call numbers for now,
             * although ideally it might be nice to limit to call numbers
             * with owning_lib matching the holding_lib of the distribs
             * that ultimately relate to the items. */

            var menulist = dojo.create("menulist", {
                "editable": "true", "className": "cn"
            });
            var menupopup = dojo.create("menupopup", null, menulist, "only");

            openils.Util.uniqueObjects(this._call_number_cache, "label").
                forEach(
                    function(cn) {
                        dojo.create(
                            "menuitem", {
                                "value": cn.label(), "label": cn.label()
                            }, menupopup, "last"
                        );
                    }
                );

            return menulist;
        } else {
            /* In this case, limit call numbers by owning_lib matching
             * distributions's holding_lib. */

            var lib = item.stream().distribution().holding_lib().id();
            if (!this._prepared_call_number_controls[lib]) {
                var menulist = dojo.create("menulist", {
                    "editable": "true", "className": "cn"
                });
                var menupopup = dojo.create("menupopup", null, menulist,"only");
                this._call_number_cache.filter(
                    function(cn) { return cn.owning_lib() == lib; }
                ).forEach(
                    function(cn) {
                        dojo.create(
                            "menuitem", {
                                "value": cn.label(), "label": cn.label()
                            }, menupopup, "last"
                        );
                    }
                );
                this._prepared_call_number_controls[lib] = menulist;
            }
            return dojo.clone(this._prepared_call_number_controls[lib]);
        }
    };

    this._build_batch_location_dropdown = function() {
        var menulist = dojo.create("menulist");
        var menupopup = dojo.create("menupopup",null,menulist);
        dojo.create("menuitem", {"value": -1, "label": "---"}, menupopup);

        fieldmapper.standardRequest(
            ["open-ils.circ",
                "open-ils.circ.copy_location.retrieve.distinct.atomic"],{
                "params": [],
                "async": false,
                "onresponse": function(r) {
                    if (list = openils.Util.readResponse(r)) {
                        list.forEach(
                            function(locname) {
                                dojo.create(
                                    "menuitem", {
                                        "value": locname, "label": locname
                                    }, menupopup
                                );
                            }
                        );
                    }
                }
            }
        );

        return menulist;
    };

    this._build_print_routing_toggle = function(item) {
        var start = true;
        var checkbox = dojo.create(
            "checkbox", {
                "oncommand": function(ev) {
	                self._print_routing(item.id(), ev.target.checked);
                },
                "checked": start.toString()
            }
        );
        this._print_routing(item.id(), start);
        return checkbox;
    }

    this._build_receive_toggle = function(item) {
        return dojo.create(
            "checkbox", {
                "oncommand": function(ev) {
	                self._disable_row(item.id(), !ev.target.checked);
                },
                "checked": "true",
                "name": "receive_" + item.id()
            }
        );
    }

    this._disable_row = function(item_id, disabled) {
        var row = this.rows[item_id];
        dojo.query(
            "textbox,menulist,checkbox:not([name^='receive_'])", row
        ).forEach(
            function(element) { element.disabled = disabled; }
        );
        this._row_disabled(row, disabled);
    };

    this._row_disabled = function(row, disabled) {
        if (typeof(row) == "string") row = this.rows[row];

        var checkbox = dojo.query("checkbox", row)[1];

        if (typeof(disabled) != "undefined")
            checkbox.checked = !disabled;

        return !checkbox.checked;
    };

    this._row_print_routing_disabled = function(row, disabled) {
        if (typeof(row) == "string") row = this.rows[row];

        var checkbox = dojo.query("checkbox", row)[0];

        if (typeof(disabled) != "undefined") {
            checkbox.checked = !disabled;
            checkbox.doCommand();
        }

        return !checkbox.checked;
    };

    this._row_field_value = function(row, field, value) {
        if (typeof(row) == "string") row = this.rows[row];

        var node = dojo.query("*", node_by_name(field, row))[0];

        if (typeof(value) == "undefined") {
            return node.value;
        } else {
            /* XXX The new two lines /should/ each do the same thing, but
             * apparently they don't.  With only one or the other, I get
             * skipped fields when this is called by the code that
             * pre-populates fields based on copy templates.  This may
             * have something to do with Dojo and XUL not getting along
             * completely? */
            dojo.attr(node, "value", value);
            node.value = value;
        }
    }

    this._print_routing = function(id, value) {
        this._wants_print_routing[id] = value;
    };

	this._user_wants_autogen = function() {
        return dojo.byId("autogen_barcodes").checked;
    };

    this._get_autogen_potentials = function(item_id) {
        var hit_a_wall = false;

        return [openils.Util.objectProperties(this.rows).sort(num_sort).filter(
            function(id) {
                if (hit_a_wall) {
                    return false;
                } else if (id <= item_id || self._row_disabled(id)) {
                    return false;
                } else if (self._row_field_value(id, "barcode")) {
                    hit_a_wall = true;
                    return false;
                } else {
                    return true;
                }
            }
        ), hit_a_wall];
    };

    this._prepare_autogen_control = function() {
        dojo.attr("autogen_barcodes",
            "command", function(ev) {
                if (!ev.target.checked) {
                    var list = self._have_autogen_barcodes();
                    if (list.length && confirm(S("autogen_barcodes.remove"))) {
                        list.forEach(
                            function(id) {
                                self._row_field_value(id, "barcode", "");
                                self.rows[id]._has_autogen_barcode = false;
                            }
                        );
                    }
                }
            }
        );
    };

    this._have_autogen_barcodes = function() {
        var list = [];
        for (var id in this.rows)
            if (this.rows[id]._has_autogen_barcode) list.push(id);
        return list;
    };

    this._cn_exists_but_not_for_lib = function(lib, value) {
        var exists = this._call_number_cache.filter(
            function(cn) { return cn.label() == value }
        );
        var for_lib = exists.filter(
            function(cn) { return cn.owning_lib() == lib; }
        );
        return (exists.length && !for_lib.length);
    };

    this._call_number_confirm_for_lib = function(lib, value) {
        if (!this._has_confirmed_cn_for)
            this._has_confirmed_cn_for = {};

        if (typeof(this._has_confirmed_cn_for[lib.id()]) == "undefined") {
            if (this._cn_exists_but_not_for_lib(lib.id(), value)) {
                this._has_confirmed_cn_for[lib.id()] = confirm(
                    F("cn_for_lib", [lib.shortname()])
                );
            } else {
                this._has_confirmed_cn_for[lib.id()] = true;
            }
        }

        return this._has_confirmed_cn_for[lib.id()];
    }

    this._confirm_row_field_application = function(id, key, value) {
        if (key == "call_number") { /* XXX make a dispatch table so we can do
                                       this for other fields too */
            return this._call_number_confirm_for_lib(
                this.item_cache[id].stream().distribution().holding_lib(),
                value
            );
        } else {
            return true;
        }
    };

    this._location_by_name = function(id, value) {
        var lib = this.item_cache[id].stream().distribution().
            holding_lib().id();
        var winners = this._location_by_lib[lib].filter(
            function(loc) { return loc.name() == value; }
        );
        if (winners.length) {
            return winners[0].id();
        } else {
            return null;
        }
    };

    this._set_all_enabled_rows = function(key, value) {
        /* do NOT do trimming here, set whitespace as is. */
        for (var id in this.rows) {
            if (!this._row_disabled(id)) {
                if (this._confirm_row_field_application(id, key, value)) {
                    if (key == "location") /* kludge for this field */ {
                        if (actual = this._location_by_name(id, value))
                            this._row_field_value(id, key, actual);
                    } else {
                        this._row_field_value(id, key, value);
                    }
                }
            }
        }
    };

    this.print_routing_lists = function(streams) {
        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.routing_list_users.fleshed_and_ordered.atomic"],{
                "params": [
                    this.authtoken, streams.map(function(o) { return o.id(); })
                ],
                "async": false,
                "oncomplete": function(r) {
                    if ((r = openils.Util.readResponse(r)) && r.length) {
                        openils.XUL.newTabEasy(
                            "SERIAL_PRINT_ROUTING_LIST_USERS",
                            S("print_routing_list_users"), {
                                "show_print_button": false, /* we supply one */
                                "routing_list_data": {
                                    "streams": streams, "mvr": self.bibdata.mvr,
                                    "issuance": self.issuance, "users": r
                                }
                            }, true /* wrap_in_browser */
                        );
                    }
                }
            }
        );
    };

    this.bib_lookup = function(bib_search_term, evt, is_actual_id, sub_id) {
        if (evt && evt.keyCode != 13) return;

        if (!bib_search_term) {
            var bib_search_term = dojo.byId("bib_search_term").value.trim();
            if (!bib_search_term.length) {
                alert(S("bib_lookup.empty"));
                return;
            }
        }

        hide("batch_receive_sub");
        hide("batch_receive_entry");

        busy(true);
        dojo.byId("bib_lookup_submit").disabled = true;
        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.biblio.record_entry.by_identifier.atomic"], {
                "params": [
                    bib_search_term, {
                        "require_subscriptions": true,
                        "add_mvr": true,
                        "is_actual_id": is_actual_id
                    }
                ],
                "async": false,
                "oncomplete": function(r) {
                    /* These two things better come before readResponse(),
                     * which can throw exceptions. */
                    busy(false);
                    dojo.byId("bib_lookup_submit").disabled = false;

                    var list = openils.Util.readResponse(r, false, true);
                    if (list && list.length) {
                        if (list.length > 1) {
                            /* XXX TODO just let the user pick one from a list,
                             * although this circumstance seems really
                             * unlikely.  It just can't happen for TCN, and
                             * wouldn't be likely for ISxN or UPC... ? */
                            alert(S("bib_lookup.multiple"));
                        } else {
                            self.bibdata = list[0];
                            self._show_bibdata_bits();
                            self.choose_subscription(sub_id);
                        }
                    } else {
                        alert(S("bib_lookup.not_found"));
                        if (is_actual_id) {
                            self.init();
                        } else {
                            dojo.byId("bib_search_term").reset();
                            dojo.byId("bib_search_term").focus();
                        }
                    }
                }
            }
        );
    };

    this.choose_subscription = function(sub_id) {
        hide("batch_receive_bib");
        hide("batch_receive_entry");
        hide("batch_receive_sub_bits");
        hide("batch_receive_issuance");

        var subs = this.bibdata.bre.subscriptions();

        if (sub_id) {
            this.choose_issuance(
                subs.filter(function(o) { return o.id() == sub_id; })[0]
            );
        } else if (subs.length > 1) {
            var menulist = dojo.create("menulist", {"id": "sub_chooser"});
            var menupopup = dojo.create("menupopup", {}, menulist, "only");

            this.bibdata.bre.subscriptions().forEach(
                function(sub) {
                    dojo.create(
                        "menuitem", {
                            "label": self._sub_label(sub),
                            "value": sub.id()
                        }, menupopup, "last"
                    );
                }
            );

            hard_empty(dojo.byId("sub_chooser_here"));

            dojo.place(menulist, dojo.byId("sub_chooser_here"), "only");
            show("batch_receive_sub");
        } else {
            this.choose_issuance(subs[0]);
        }
    };

    this.choose_issuance = function(sub) {
        hide("batch_receive_bib");
        hide("batch_receive_entry");
        hide("batch_receive_sub");

        if (typeof(sub) == "undefined") {   /* sub chosen from menu */
            var sub_id = dojo.byId("sub_chooser").value;
            this.sub = this.bibdata.bre.subscriptions().filter(
                function(o) { return o.id() == sub_id; }
            )[0];
        } else {    /* only one sub possible, passed in directly */
            this.sub = sub;
        }

        this._show_sub_bits();

        this.issuances = this._get_receivable_issuances();   /* sync */

        if (this.issuances.length > 1) {
            var menulist = dojo.create("menulist", {"id": "issuance_chooser"});
            var menupopup = dojo.create("menupopup", {}, menulist, "only");

            this.issuances.sort(
                function(a, b) {
                    if (a.date_published()>b.date_published()) return 1;
                    else if (b.date_published()>a.date_published()) return -1;
                    else return 0;
                }
            ).forEach(
                function(issuance) {
                    dojo.create(
                        "menuitem", {
                            "label": issuance.label(),
                            "value": issuance.id()
                        }, menupopup, "last"
                    );
                }
            );

            hard_empty("issuance_chooser_here");
            dojo.place(menulist, dojo.byId("issuance_chooser_here"), "only");

            show("batch_receive_issuance");
        } else if (this.issuances.length) {
            this.load_entry_form(this.issuances[0]);
        } else {
            alert(S("issuance_lookup.none"));
            this.init();
        }

    };

    this._update_copy_template_cache = function() {
        var templates_needed = openils.Util.uniqueElements(
            openils.Util.objectProperties(this.item_cache).map(
                function(id) {
                    return self.item_cache[id].stream().distribution().
                        receive_unit_template();
                }
            )
        ).filter(
            function(id) { return !self._copy_template_cache[id]; }
        );

        if (templates_needed.length) {
            this.pcrud.search("act", {"id": templates_needed}).forEach(
                function(tmpl) {
                    self._copy_template_cache[tmpl.id()] = tmpl;
                }
            );
        }
    }

    this.apply_copy_templates = function() {
        this._update_copy_template_cache(); /* sync */

        for (var id in this.item_cache) {
            var item = this.item_cache[id];
            var template_id =
                item.stream().distribution().receive_unit_template();
            var template = this._copy_template_cache[template_id];

            var row = this.rows[id];

            var tmpl_mod = template.circ_modifier();
            var tmpl_loc = template.location();
            var tmpl_price = template.price();
            if (tmpl_mod != null) {
                this._row_field_value(
                    row, "circ_modifier", tmpl_mod == "" ? 0 : tmpl_mod
                );
            }
            if (tmpl_loc)
                this._row_field_value(row, "location", tmpl_loc);
            if (tmpl_price > 0)
                this._row_field_value(row, "price", tmpl_price);
        }
    };

    this.load_entry_form = function(issuance) {
        if (typeof(issuance) == "undefined") {
            var issuance_id = dojo.byId("issuance_chooser").value;
            this.issuance = this.issuances.filter(
                function(o) { return o.id() == issuance_id; }
            )[0];
        } else {
            this.issuance = issuance;
        }

        this._show_issuance_bits();
        this._prepare_autogen_control();

        busy(true);

        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.items.receivable.by_issuance.atomic"], {
                "params": [this.authtoken, this.issuance.id()],
                "async": true,
                "onresponse": function(r) {
                    busy(false);

                    if (list = openils.Util.readResponse(r, false, true)) {
                        if (list.length) {
                            busy(true);
                            show("form_holder");

                            list.forEach(function(o) {self.add_entry_row(o);});

                            self.build_batch_entry_row();

                            var recv_with_units =
                                dojo.byId("batch_receive_with_units");
                            recv_with_units.doCommand();
                            if (recv_with_units.checked)
                                self.apply_copy_templates();

                            show("batch_receive_entry");
                            busy(false);
                        } else {
                            alert(S("item_lookup.none"));
                            if (self.issuances.length) self.choose_issuance();
                            else self.init();
                        }
                    }
                }
            }
        );
    };

    this.toggle_receive_with_units = function(ev) {
        var head_row = dojo.byId("batch_receive_entry_thead");
        var batch_row = dojo.byId("entry_batch_row");

        var fields = [
            "barcode", "call_number", "price", "location", "circ_modifier"
        ];

        var table_cell_func = ev.target.checked ?
            show_table_cell : hide_table_cell;
        fields.forEach(
            function(key) {
                if (batch_row) table_cell_func(node_by_name(key, batch_row));
                if (head_row) table_cell_func(node_by_name(key, head_row));

                for (var id in self.rows) {
                    table_cell_func(node_by_name(key, self.rows[id]));
                }
            }
        );

        if (!ev.target.checked) {
            /* XXX As of the time of this writing, a blank barcode field will
             * avoid unit creation */
            this._set_all_enabled_rows("barcode", "");
        }
    };

    this.toggle_all_receive = function(checked) {
        for (var id in this.rows) {
            this._disable_row(id, !checked);
        }
    };

    this.toggle_all_print_routing = function(checked) {
        for (var id in this.rows) {
            this._row_print_routing_disabled(id, !checked);
        }
    };

    this.build_batch_entry_row = function() {
        var row = dojo.byId("entry_batch_row");

        this.batch_controls = {};

        node_by_name("note", row).appendChild(
            this.batch_controls.note = dojo.create("textbox", {"size": 20})
        );

        node_by_name("location", row).appendChild(
            this.batch_controls.location =
                this._build_batch_location_dropdown()
        );

        node_by_name("circ_modifier", row).appendChild(
            this.batch_controls.circ_modifier =
                this._extend_circ_modifier_for_batch(
                    this._build_circ_modifier_dropdown() /* for all OUs */
                )
        );

        node_by_name("call_number", row).appendChild(
            this.batch_controls.call_number = this._build_call_number_control()
        );

        node_by_name("price", row).appendChild(
            this.batch_controls.price = dojo.create("textbox", {"size": 9})
        );

        node_by_name("print_routing", row).appendChild(
            dojo.create(
                "checkbox", {
                    "oncommand": function(ev) {
                        self.toggle_all_print_routing(ev.target.checked);
                    },
                    "checked": "true"
                }
            )
        );

        node_by_name("receive", row).appendChild(
            dojo.create(
                "checkbox", {
                    "oncommand": function(ev) {
                        self.toggle_all_receive(ev.target.checked);
                    },
                    "checked": "true"
                }
            )
        );

        node_by_name("apply", row).appendChild(
            dojo.create("button", {
                "label": S("apply"),
                "oncommand": function() { self.apply_batch_values(); }
            })
        );
    };

    this.apply_batch_values = function() {
        var row = dojo.byId("entry_batch_row");

        for (var key in this.batch_controls) {
            var value = this.batch_controls[key].value;
            if (value != "" && value != -1)
                this._set_all_enabled_rows(key, value);
        }

        /* XXX genericize for all fields? */
        delete this._has_confirmed_cn_for;
    };

    this.add_entry_row = function(item) {
        this.item_cache[item.id()] = item;
        var row = this.rows[item.id()] = dojo.clone(this.template);

        function n(s) { return node_by_name(s, row); }    /* typing saver */

        var stream_dist_label = item.stream().distribution().label();
        if (item.stream().routing_label())
            stream_dist_label += " / " + item.stream().routing_label();

        n("holding_lib").appendChild(
            dojo.create(
                "description", {
                    "value": item.stream().distribution().
                        holding_lib().shortname(),
                    "tooltiptext": stream_dist_label
                }
            )
        );

        n("barcode").appendChild(
            dojo.create(
                "textbox", {
                    "size": 15,
                    "tabindex": 10000 + Number(item.id()), /* is this right? */
                    "onchange": function() {
                        self.autogen_if_appropriate(this, item.id());
                    }
                }
            )
        );

        n("location").appendChild(
            this._build_location_dropdown(
                this._get_locations_for_lib(
                    item.stream().distribution().holding_lib().id()
                )
            )
        );

        n("note").appendChild(dojo.create("textbox", {"size": 20}));
        n("circ_modifier").appendChild(this._build_circ_modifier_dropdown());
        n("call_number").appendChild(this._build_call_number_control(item));
        n("price").appendChild(dojo.create("textbox", {"size": 9}));
        n("print_routing").appendChild(this._build_print_routing_toggle(item));
        n("receive").appendChild(this._build_receive_toggle(item));

        this.entry_tbody.appendChild(row);
    };

    this.receive = function() {
        var items = [];
        var confirmed_missing_units = false;

        for (var id in this.rows) {
            if (this._row_disabled(id))
                continue;

            var item = this.item_cache[id];

            /* Don't trim() call_number field, as existing call numbers
             * are yielded by their label field, not by id, and if
             * they start or end in spaces, we'll unintentionally create
             * a new, different CN if we trim that */
            var cn_string = this._row_field_value(id, "call_number");
            var barcode = this._row_field_value(id, "barcode");
            if (barcode && barcode.trim) barcode = barcode.trim();

            if (barcode && cn_string.length) {
                var unit = new sunit();
                unit.barcode(barcode);

                ["price", "location", "circ_modifier"].forEach(
                    function(field) {
                        var value = self._row_field_value(id, field);
                        if (value)
                            unit[field](value.trim ? value.trim() : value);
                    }
                );

                unit.call_number(cn_string);
                item.unit(unit);
            } else if (barcode && !cn_string.length) {
                alert(S("missing_cn"));
                return;
            } else if (!confirmed_missing_units) {
                if (
                    (!dojo.byId("batch_receive_with_units").checked) ||
                    confirm(S("missing_units"))
                ) {
                    confirmed_missing_units = true;
                } else {
                    return;
                }
            }

            var note_value = this._row_field_value(id, "note").trim();
            if (note_value) {
                var note = new sin();
                note.item(id);
                note.pub(false);
                note.title(S("receive_time_note"));
                note.value(note_value);

                item.notes([note]);
            }

            items.push(item);
        }

        busy(true);
        fieldmapper.standardRequest(
            ["open-ils.serial", "open-ils.serial.receive_items.one_unit_per"],{
                "params": [this.authtoken, items, this.sub.record_entry()],
                "async": true,
                "oncomplete": function(r) {
                    try {
                        var streams_for_printing = [];
                        while (item_id = openils.Util.readResponse(r)) {
                            if (self._wants_print_routing[item_id]) {
                                streams_for_printing.push(
                                    self.item_cache[item_id].stream()
                                );
                            }
                            self.finish_receipt(item_id);
                        }
                        if (streams_for_printing.length)
                            self.print_routing_lists(streams_for_printing);
                    } catch (E) {
                        alert(E);
                    }
                    busy(false);
                    try {
                        xulG.reload_opac();
                    } catch(E) {
                        (dump ? dump : console.log)(E);
                    }
                }
            }
        );
    };

    this.finish_receipt = function(item_id) {
        hard_empty(this.rows[item_id]);
        dojo.destroy(this.rows[item_id]);
        delete this.rows[item_id];
        delete this.item_cache[item_id];
    };

    this.autogen_if_appropriate = function(textbox, item_id) {
        if (this._user_wants_autogen() && textbox.value) {
            var kvlist = this._get_autogen_potentials(item_id);
            var list = kvlist[0];
            var question = kvlist[1];
            if (list.length) {
                if (question && !confirm(S("autogen_barcodes.questionable")))
                    return;

                busy(true);
                try {
                    fieldmapper.standardRequest(
                        ["open-ils.cat", "open-ils.cat.item.barcode.autogen"], {
                            "params": [
                                this.authtoken, textbox.value, list.length
                            ],
                            "async": false,
                            "onresponse": function(r) {
                                r = openils.Util.readResponse(r, false, true);
                                if (r) {
                                    for (var i = 0; i < r.length; i++) {
                                        var row = self.rows[list[i]];
                                        self._row_field_value(
                                            row, "barcode", r[i]
                                        );
                                        row._has_autogen_barcode = true;
                                    }
                                }
                            }
                        }
                    );
                } catch (E) {
                    alert(E);
                }
                busy(false);
            } /* do nothing for empty list */
        }
    };

    this.init.apply(this, arguments);
}

function my_init() {
    var cgi = new openils.CGI();
    var authtoken = (typeof ses == "function" ? ses() : 0) ||
            cgi.param("ses") || dojo.cookie("ses");
    if(!authtoken && openils.XUL.isXUL()) {
        var stash = openils.XUL.getStash();
        authtoken = stash.session.key;
    }
    batch_receiver = new BatchReceiver(
        authtoken,
        cgi.param("docid") || null, cgi.param("subid") || null
    );
}

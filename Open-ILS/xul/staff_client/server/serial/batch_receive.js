dojo.require("dojo.cookie");
dojo.require("dojo.date.locale");
dojo.require("dojo.date.stamp");
dojo.require("openils.Util");
dojo.require("openils.CGI");

var authtoken;
var batch_receiver;

String.prototype.trim = function() {return this.replace(/^\s*(.+)\s*$/,"$1");}

/**
 * hard_empty() is needed because dojo.empty() doesn't seem to work on
 * XUL nodes. This also means that dojo.place() with a position argument of
 * "only" doesn't do what it should, but calling hard_empty() on the refnode
 * first will do the trick.
 */
function hard_empty(node) {
    if (typeof(node) == "string")
        node = dojo.byId(node);
    if (node)
        dojo.forEach(node.childNodes, dojo.destroy);
}

function hide(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    openils.Util.addCSSClass(e, "hideme");
}

function show(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    openils.Util.removeCSSClass(e, "hideme");
}

function busy(on) {
    if (typeof(busy._window) == "undefined")
        busy._window = dojo.query("window")[0];
    busy._window.style.cursor = on ? "wait" : "auto";
}

function S(k) {
    return dojo.byId("serialStrings").getString("batch_receive." + k).
        replace("\\n", "\n");
}

function T(s) { return document.createTextNode(s); }
function D(s) {return s ? openils.Util.timeStamp(s,{"selector":"date"}) : "";}
function node_by_name(s, ctx) {return dojo.query("[name='"+ s +"']",ctx)[0];}

function num_sort(a, b) {
    [a, b] = [Number(a), Number(b)];
    return a > b ? 1 : (a < b ? -1 : 0);
}

function BatchReceiver() {
    var self = this;

    this._init = function(bib_id) {
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

        this._location_by_lib = {};

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
            this.bib_lookup(bib_id, null, true);

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
                    "params": [authtoken, this.sub.id()],
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
                                            /* XXX use format string */
                                            "label": mod.code()+" "+mod.name()
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
                        "value": loc.id(),
                        "label": "(" + loc.owning_lib().shortname() + ") " +
                            loc.name() /* XXX i18n */
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

    this._build_receive_toggle = function(item) {
        return dojo.create(
            "checkbox", {
                "oncommand": function(ev) {
	                self._disable_row(item.id(), !ev.target.checked);
                },
                "checked": "true"
            }
        );
    }

    this._disable_row = function(item_id, disabled) {
        var row = this.rows[item_id];
        dojo.query("textbox,menulist", row).forEach(
            function(element) { element.disabled = disabled; }
        );
    };

    this._row_disabled = function(row) {
        if (typeof(row) == "string") row = this.rows[row];
        return !dojo.query("checkbox", row)[0].checked;
    };

    this._row_field_value = function(row, field, value) {
        if (typeof(row) == "string") row = this.rows[row];

        var node = dojo.query("*", node_by_name(field, row))[0];

        if (typeof(value) == "undefined")
            return node.value;
        else
            node.value = value;
    }

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

    this._set_all_enabled_rows = function(key, value) {
        /* do NOT do trimming here, set whitespace as is. */
        for (var id in this.rows) {
            if (!this._row_disabled(id))
                this._row_field_value(id, key, value);
        }
    };

    this.bib_lookup = function(bib_search_term, evt, is_actual_id) {
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
                            self.choose_subscription();
                        }
                    } else {
                        alert(S("bib_lookup.not_found"));
                        if (is_actual_id) {
                            self._init();
                        } else {
                            dojo.byId("bib_search_term").reset();
                            dojo.byId("bib_search_term").focus();
                        }
                    }
                }
            }
        );
    };

    this.choose_subscription = function() {
        hide("batch_receive_bib");
        hide("batch_receive_entry");
        hide("batch_receive_sub_bits");
        hide("batch_receive_issuance");

        var subs = this.bibdata.bre.subscriptions();

        if (subs.length > 1) {
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
            this._init();
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
                "params": [authtoken, this.issuance.id()],
                "async": true,
                "onresponse": function(r) {
                    busy(false);

                    if (list = openils.Util.readResponse(r, false, true)) {

                        if (list.length) {
                            busy(true);
                            show("form_holder");

                            list.forEach(function(o) {self.add_entry_row(o);});
                            if (list.length > 1) {
                                self.build_batch_entry_row();
                                show("batch_receive_entry");
                            }

                            busy(false);
                        } else {
                            alert(S("item_lookup.none"));
                            if (self.issuances.length) self.choose_issuance();
                            else self._init();
                        }
                    }
                }
            }
        );

    };

    this.build_batch_entry_row = function() {
        var row = dojo.byId("entry_batch_row");

        this.batch_controls = {};

        node_by_name("note", row).appendChild(
            this.batch_controls.note = dojo.create("textbox", {"size": 20})
        );

        node_by_name("location", row).appendChild(
            this.batch_controls.location = this._build_location_dropdown(
                /* XXX TODO build a smarter list. rather than all copy locs
                 * under OU #1, try building a list of copy locs available to
                 * all OUs represented in actual items */
                this._get_locations_for_lib(1),
                true /* add_unset_value */
            )
        );

        node_by_name("circ_modifier", row).appendChild(
            this.batch_controls.circ_modifier =
                this._extend_circ_modifier_for_batch(
                    this._build_circ_modifier_dropdown()
                )
        );

        node_by_name("price", row).appendChild(
            this.batch_controls.price = dojo.create("textbox", {"size": 9})
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
    };

    this.add_entry_row = function(item) {
        this.item_cache[item.id()] = item;
        var row = this.rows[item.id()] = dojo.clone(this.template);

        function n(s) { return node_by_name(s, row); }    /* typing saver */

        n("holding_lib").appendChild(
            T(item.stream().distribution().holding_lib().shortname())
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
        n("price").appendChild(dojo.create("textbox", {"size": 9}));
        n("receive").appendChild(this._build_receive_toggle(item));

        this.entry_tbody.appendChild(row);
    };

    this.receive = function() {
        var items = [];
        for (var id in this.rows) {
            if (this._row_disabled(id)) 
                continue;

            var item = this.item_cache[id];

            var barcode = this._row_field_value(id, "barcode");
            if (barcode) {
                var unit = new sunit();
                unit.barcode(barcode);

                ["price", "location", "circ_modifier"].forEach(
                    function(field) {
                        var value = self._row_field_value(id, field).trim();
                        if (value) unit[field](value);
                    }
                );


                item.unit(unit);
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
                "params": [authtoken, items],
                "async": true,
                "oncomplete": function(r) {
                    try {
                        while (item_id = openils.Util.readResponse(r))
                            self.finish_receipt(item_id);
                    } catch (E) {
                        alert(E);
                    }
                    busy(false);
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
            var [list, question] = this._get_autogen_potentials(item_id);
            if (list.length) {
                if (question && !confirm(S("autogen_barcodes.questionable")))
                    return;

                busy(true);
                try {
                    fieldmapper.standardRequest(
                        ["open-ils.cat", "open-ils.cat.item.barcode.autogen"], {
                            "params": [authtoken, textbox.value, list.length],
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

    this._init.apply(this, arguments);
}

function my_init() {
    var cgi = new openils.CGI();

    authtoken = (typeof ses == "function" ? ses() : 0) ||
        cgi.param("ses") || dojo.cookie("ses");

    batch_receiver = new BatchReceiver(cgi.param("docid") || null);
}

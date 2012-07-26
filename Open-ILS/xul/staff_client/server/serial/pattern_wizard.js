/* The code in this file relies on common.js */

dojo.require("openils.Util");

var wizard;

function S(k) {
    return dojo.byId("serialStrings").getString("pattern_wizard." + k).
        replace("\\n", "\n");
}

var _chronstants = {    /* snicker */
    "month": {
        "values": [
            "01", "02", "03", "04", "05", "06",
            "07", "08", "09", "10", "11", "12"
        ]
    },
    "weekday": {
        "values": ["mo", "tu", "we", "th", "fr", "sa", "su"]
    },
    "week": {
        "values": ["00", "01", "02", "03", "04", "05", "97", "98", "99"]
    },
    "season": {
        "values": ["21", "22", "23", "24"]
    }
};

function _menulist(values, labels, items_only) {
    var menuitems = [];
    for (var i = 0; i < values.length; i++) {
        menuitems.push(
            dojo.create(
                "menuitem", {"value": values[i], "label": labels[i]}
            )
        );
    }
    if (items_only) {
        return menuitems;
    } else {
        var menupopup = dojo.create("menupopup");
        menuitems.forEach(
            function(menuitem) { dojo.place(menuitem, menupopup, "last"); }
        );
        var menulist = dojo.create("menulist");
        dojo.place(menupopup, menulist, "only");
        return menulist;
    }
}

function _cap_number_textbox_value(node, max) {
    if (node.value > max) node.value = max;
    node.max = max;
}

function _cap_to_month(month, date_box) {
    if (!date_box)
        return;

    if (month == "02") {
        _cap_number_textbox_value(date_box, 29);
    } else if (
        ["09", "04", "06", "11"].indexOf(month) != -1
    ) {
        _cap_number_textbox_value(date_box, 30);
    } else {
        _cap_number_textbox_value(date_box, 31);
    }
}

function CalendarChangeRow() {
    var self = this;

    this._init = function(template, id, manager) {
        this.element = dojo.clone(template);

        this.point_widgets = ["month", "season", "date"].map(
            function(type) { return node_by_name(type, self.element); }
        );

        dojo.attr(
            node_by_name("type", this.element), "oncommand", function(ev) {
                self.point_widgets.forEach(
                    function(w) {
                        var active = (dojo.attr(w, "name") == ev.target.value);
                        (active ? show : hide)(w);
                    }
                );
            }
        );

        dojo.attr(
            node_by_name("date_month", this.element),
            "oncommand",
            function(ev){
                _cap_to_month(
                    ev.target.value, node_by_name("date_day", self.element)
                );
            }
        );

        this.remover = node_by_name("remover", this.element);
        dojo.attr(
            this.remover, "onclick", function() { manager.remove_row(id); }
        );
    };

    this._compile_month = function() {
        return node_by_name("month", this.element).value;
    };

    this._compile_season = function() {
        return node_by_name("season", this.element).value;
    };

    this._compile_date = function() {
        var n = Number(node_by_name("date_day", this.element).value);
        if (n < 10)
            n = "0" + String(n);
        else
            n = String(n);

        return node_by_name("date_month", this.element).value + n;
    };

    this.compile = function() {
        var type = node_by_name("type", this.element).value;

        return type ? this["_compile_" + type]() : [];
    };

    this._init.apply(this, arguments);
};

function RegularityRow() {
    var self = this;

    this._init = function(template, id, manager) {
        this.id = id;
        this.manager = manager;
        this.element = dojo.clone(template);

        this.publication_code = null;
        this.type_and_code_pattern = null;

        this._prepare_event_handlers(id);
    };

    this._prepare_event_handlers = function(id) {
        dojo.attr(
            node_by_name("remove", this.element),
            "oncommand",
            function() { self.manager.remove_row(id); }
        );
        dojo.attr(
            node_by_name("poc", this.element),
            "oncommand",
            function(ev) {
                self.publication_code = ev.target.value;
                self.update_chron_code_controls();
            }
        );
        dojo.attr(
            node_by_name("type_and_code_pattern", this.element),
            "oncommand",
            function(ev) {
                self.type_and_code_pattern = ev.target.value;
                self.update_chron_code_controls();
            }
        );

        this.add_sub_row_btn = node_by_name("add_sub_row", this.element);
        dojo.attr(
            this.add_sub_row_btn, "oncommand", function(ev) {
                self.add_sub_row();
            }
        );
    };

    this.add_sub_row = function() {
        var container = dojo.create(
            "hbox", null, node_by_name("sub_rows_here", this.element), "last"
        );

        /* Break up our type and code pattern into parts that can be
         * mapped to widgets. */
        this.get_code_pattern().map(
            function(pattern) {
                return self.manufacture_chron_code_control(pattern);
            }
        ).forEach(
            function(control) {
                dojo.place(control, container, "last");
            }
        );

        /* special case: add a label for clarity for MMWW */
        if (this.type_and_code_pattern == "w:MMWW")
            dojo.create("description", {"value": S("week")}, container, "last");

        /* another special case: YYYY needs no add/remove subrow buttons */
        if (this.type_and_code_pattern == "y:YYYY") {
            this.add_sub_row_btn.disabled = true;
        } else {
            this.add_sub_row_btn.disabled = false;

            dojo.create(
                "button", {
                    "style": {
                        "fontWeight": "bold", "color": "red"
                    },
                    "label": "X",
                    "tooltiptext": S("remove_sub_row"),
                    "oncommand": function() {
                        hard_empty(container); dojo.destroy(container);
                    }
                }, container, "last"
            );
        }
    };

    this.get_code_pattern = function() {
        var code_pattern_str = this.type_and_code_pattern.split(":")[1];

        /* A special case: if the strings is YYYY, return it whole. Otherwise
         * break it up into two-char parts. These parts come from the
         * "Possible Code Pattern" column of "Chronology Type and Code
         * Patterns" of the subfield $y section of the document at
         * http://www.loc.gov/marc/holdings/hd853855.html
         *
         * In retrospect, there was no reason to adopt these multi-char
         * code patterns for this purpose. Something single-char and
         * quicker to decode would have sufficed, but meh, this works.
         */
        if (code_pattern_str[0] == "Y")
            return [code_pattern_str];

        var code_pattern = [];
        for (var i=0; code_pattern_str[i]; i+=2)
            code_pattern.push(code_pattern_str.slice(i, i + 2));

        return code_pattern;
    };

    this.allow_year_split = function(yes) {
        dojo.attr(
            dojo.query("[value='y:YYYY']",dojo.query("[name='type_and_code_pattern']")[0])[0],
            "disabled",
            !yes
        );
    };

    this.update_chron_code_controls = function() {
        if (!this.type_and_code_pattern || !this.publication_code)
            return;

        this.allow_year_split(this.publication_code != "c");

        var container = node_by_name("sub_rows_here", this.element);
        /* for some reason, this repeitition is necessary with XUL documents
         * and dojo */
        for (var i = 0 ; i < 2; i++) {
            hard_empty(container);
            dojo.forEach(container.childNodes, dojo.destroy);
        }

        this.add_sub_row();
    };

    this.manufacture_chron_code_control = function(pattern) {
        return {
            "dd": function() {
                return _menulist(
                    _chronstants.weekday.values, _chronstants.weekday.names
                );
            },
            "DD": function() {
                return dojo.create( /* XXX TODO change min/max based on month */
                    "textbox", {
                        "size": 3,
                        "type": "number",
                        "min": 1,
                        "max": 31
                    }
                );
            },
            "MM": function() {
                var mm = _menulist(
                    _chronstants.month.values, _chronstants.month.names
                );
                dojo.attr(
                    mm, "oncommand", function(ev) {
                        _cap_to_month(
                            dojo.attr(ev.target, "value"),
                            dojo.query(
                                'textbox[type="number"]',
                                ev.target.parentNode.parentNode.parentNode
                                /* ev.target is the menuITEM node */
                            )[0]
                        );
                    }
                );
                return mm;
            },
            "SS": function() {
                return _menulist(
                    _chronstants.season.values, _chronstants.season.names
                );
            },
            "WW": function() {
                return _menulist(
                    _chronstants.week.values, _chronstants.week.names
                );
            },
            "YYYY": function() {
                return dojo.create(
                    "textbox", {
                        "disabled": "true", "value": "yyy1/yyy2", "size": 9
                    }
                );
            }
        }[pattern]();
    };

    this.compile = function() {
        return this.publication_code +
            this.type_and_code_pattern[0] +
            dojo.query("hbox", node_by_name("sub_rows_here", this.element)).map(
                function(sub_row) {
                    var t = "";
                    dojo.filter(
                        sub_row.childNodes, function(n) {
                            return (
                                n.nodeName == "menulist" ||
                                n.nodeName == "textbox"
                            );
                        }
                    ).forEach(
                        function(control) {
                            if (control.value.match(/^\d$/))
                                t += "0" + control.value;
                            else
                                t += control.value;
                        }
                    );
                    return t;
                }
            ).join(this.publication_code == "c" ? "/" : ",");
    };

    this._init.apply(this, arguments);
}

function RegularityEditor() {
    var self = this;

    this._init = function() {
        this.rows = {};
        this.row_count = 0;

        this._prepare_template();
        this.add_row();
    };

    this._prepare_template = function() {
        var tmpl = dojo.byId("regularity_template_y");
        tmpl.parentNode.removeChild(tmpl);

        this.template = tmpl;
    };

    this.toggle = function(ev) {
        this.active = ev.target.checked;
        (this.active ? show : hide)("regularity_editor_here");
    };

    this.add_row = function() {
        var id = this.row_count++;

        this.rows[id] = new RegularityRow(this.template, id, this);

        dojo.place(this.rows[id].element, "y_rows_here", "last");
    };

    this.remove_row = function(id) {
        var row = this.rows[id];
        hard_empty(row.element);
        dojo.destroy(row.element);

        delete this.rows[id];
    };

    this.compile = function() {
        if (!this.active) {
            return [];
        } else {
            return openils.Util.objectProperties(this.rows).sort().reduce(
                function(a, b){return a.concat(["y",self.rows[b].compile()]);},
                []
            );
        }
    };

    this._init.apply(this, arguments);
}

function CalendarChangeEditor() {
    var self = this;

    this._init = function() {
        this.rows = {};
        this.row_count = 0;

        this._get_template();
        this.add_row();
    };

    this._get_template = function() {
        var temp_template = dojo.byId("calendar_row_template");
        this.grid = temp_template.parentNode;
        this.template = this.grid.removeChild(temp_template);
        this.template.removeAttribute("id");

        [
            dojo.query("[name='month']", this.template)[0],
            dojo.query("[name='date_month']", this.template)[0]
        ].forEach(
            function(menupopup) {
                menupopup = dojo.query("menupopup", menupopup)[0];
                _menulist(
                    _chronstants.month.values,
                    _chronstants.month.names,
                    /* items_only */ true
                ).forEach(
                    function(menuitem) {
                        dojo.place(menuitem, menupopup, "last");
                    }
                );
            }
        );
    };

    this.remove_row = function(id) {
        hard_empty(this.rows[id].element);
        dojo.destroy(this.rows[id].element);
        delete this.rows[id];

        dojo.byId("calendar_change_add_row").disabled = false;
    };

    this.add_row = function() {
        var id = this.row_count++;

        this.rows[id] =
            new CalendarChangeRow(dojo.clone(this.template), id, this);
        dojo.place(this.rows[id].element, this.grid, "last");
    };

    this.toggle = function(ev) {
        this.active = ev.target.checked;
        (this.active ? show : hide)("calendar_change_editor_here");
    };

    this.compile = function() {
        if (!this.active) return [];

        return [
            "x",
            openils.Util.objectProperties(this.rows).sort(num_sort).map(
                function(key) { return self.rows[key].compile(); }
            ).join(",")
        ];
    };

    this._init.apply(this, arguments);
}

function ChronRow() {
    var self = this;

    this._init = function(template, subfield, manager) {
        this.subfield = subfield;
        this.element = dojo.clone(template);

        dojo.attr(
            node_by_name("caption_label", this.element),
            "value", S("chronology." + subfield) + ":"
        );

        this.fields = {};
        ["caption", "display_in_holding"].forEach(
            function(o) { self.fields[o] = node_by_name(o, self.element); }
        );

        this.remover = node_by_name("remover", this.element);
        dojo.attr(
            this.remover, "onclick", function(){ manager.remove_row(subfield); }
        );
    };

    this._init.apply(this, arguments);
};

function ChronEditor() {
    /* TODO make this enforce unique caption values for each row? */
    var self = this;

    this._init = function() {
        this.rows = {};

        this.subfields = ["i", "j", "k", "l", "m"];

        this._get_template();
        this.add_row();
    };

    this._get_template = function() {
        var temp_template = dojo.byId("chron_row_template");
        this.grid = temp_template.parentNode;
        this.template = this.grid.removeChild(temp_template);
        this.template.removeAttribute("id");
    };

    this._test_removability = function(subfield) {
        var start = this.subfields.indexOf(subfield);

        if (start < 0) {
            /* no such field, not OK to remove */
            return false;
        } else if (!this.subfields[start]) {
            /* field row not present, not OK to remove */
            return false;
        }

        var next = this.subfields[start + 1];
        if (typeof(next) == "undefined") { /* last in set, ok to remove */
            return true;
        } else {
            if (this.rows[next]) { /* NOT last in set, not ok to remove */
                return false;
            } else { /* last in set actually present, ok to remove */
                return true;
            }
        }
    };

    this.remove_row = function(subfield) {
        if (this._test_removability(subfield)) {
            hard_empty(this.rows[subfield].element);
            dojo.destroy(this.rows[subfield].element);
            delete this.rows[subfield];

            dojo.byId("chron_add_row").disabled = false;
        } else {
            alert(S("not_removable_row"));
        }
    };

    this.add_row = function() {
        var available = this.subfields.filter(
            function(subfield) { return !Boolean(self.rows[subfield]); }
        );

        if (available.length) {
            var subfield = available.shift();
            if (!available.length)
                dojo.byId("chron_add_row").disabled = true;
        } else {
            /* We shouldn't really be able to get here. */
            return;
        }

        this.rows[subfield] =
            new ChronRow(dojo.clone(this.template), subfield, this);

        dojo.place(this.rows[subfield].element, this.grid, "last");
    };

    this.toggle = function(ev) {
        this.active = ev.target.checked;
        (this.active ? show : hide)("chron_editor_here");
    };

    this.compile = function() {
        if (!this.active) return [];

        return this.subfields.filter(
            function(subfield) { return Boolean(self.rows[subfield]); }
        ).reduce(
            function(result, subfield) {
                var caption = self.rows[subfield].fields.caption.value;
                if (!self.rows[subfield].fields.display_in_holding.checked)
                    caption = "(" + caption + ")";
                return result.concat([subfield, caption]);
            }, []
        );
    };

    this._init.apply(this, arguments);
}

function EnumRow() {
    var self = this;

    this._init = function(template, subfield, manager) {
        this.subfield = subfield;
        this.element = dojo.clone(template);

        this.fields = {};
        ["caption","units_per","units_per_number","continuity","remover"].
            forEach(
                function(o) { self.fields[o] = node_by_name(o, self.element); }
            );

        if (subfield == "a" || subfield == "g") {
            ["units_per", "continuity"].forEach(
                function(o) { soft_hide(node_by_name(o, self.element)); }
            );
        }

        var caption_id = "enum_caption_" + subfield;
        var caption_label = node_by_name("caption_label", this.element);
        dojo.attr(this.fields.caption, "id", caption_id);
        dojo.attr(caption_label, "control", caption_id);
        dojo.attr(caption_label, "value", S("enumeration." + subfield) + ":");

        this.remover = this.fields.remover;
        dojo.attr(
            this.remover, "onclick", function(){manager.remove_row(subfield);}
        );
    };

    this._init.apply(this, arguments);
};

function EnumEditor() {
    var self = this;

    this._init = function() {
        this.normal_rows = {};
        this.alt_rows = {};

        this.normal_subfields = ["a","b","c","d","e","f"];
        this.alt_subfields = ["g","h"];

        this._get_template();
        this.add_normal_row();
    };

    this._get_template = function() {
        var temp_template = dojo.byId("enum_row_template");
        this.grid = temp_template.parentNode;
        this.template = this.grid.removeChild(temp_template);
        this.template.removeAttribute("id");
    };

    this.remove_row = function(subfield) {
        if (this._test_removability(subfield)) {
            var add_button = "enum_add_normal_row";
            var set = this.normal_rows;
            if (!set[subfield]) {
                set = this.alt_rows;
                add_button = "enum_add_alt_row";
            }

            hard_empty(set[subfield].element);
            dojo.destroy(set[subfield].element);
            delete set[subfield];
            dojo.byId(add_button).disabled = false;
        } else {
            alert(S("not_removable_row"));
        }
    };

    this._test_removability = function(id) {
        var set = this.normal_subfields;
        var rows = this.normal_rows;
        var start = set.indexOf(id);

        if (start == -1) {
            set = this.alt_subfields;
            rows = this.alt_rows;
            start = set.indexOf(id);
        }

        if (start < 0) {
            /* no such field, not OK to remove */
            return false;
        } else if (!set[start]) {
            /* field row not present, not OK to remove */
            return false;
        }

        var next = set[start + 1];
        if (typeof(next) == "undefined") { /* last in set, ok to remove */
            return true;
        } else {
            if (rows[next]) { /* NOT last in set, not ok to remove */
                return false;
            } else { /* last in set actually present, ok to remove */
                return true;
            }
        }
    };

    this.add_normal_row = function() {
        var available = this.normal_subfields.filter(
            function(subfield) { return !Boolean(self.normal_rows[subfield]); }
        );
        if (available.length) {
            var subfield = available.shift();
            if (!available.length) {
                /* If that was the last available normal row, disable the
                 * add rows button. */
                dojo.byId("enum_add_normal_row").disabled = true;
            }
        } else {
            /* We shouldn't really be able to get here. */
            return;
        }

        this.normal_rows[subfield] =
            new EnumRow(dojo.clone(this.template), subfield, this);

        dojo.place(this.normal_rows[subfield].element, this.grid, "last");
    };

    this.add_alt_row = function() {
        var available = this.alt_subfields.filter(
            function(subfield) { return !Boolean(self.alt_rows[subfield]); }
        );
        if (available.length) {
            var subfield = available.shift();
            if (!available.length) {
                /* If that was the last available normal row, disable the
                 * add rows button. */
                dojo.byId("enum_add_alt_row").disabled = true;
            }
        } else {
            /* We shouldn't really be able to get here. */
            return;
        }

        this.alt_rows[subfield] =
            new EnumRow(dojo.clone(this.template), subfield, this);

        dojo.place(this.alt_rows[subfield].element, this.grid, "last");
    };

    this.toggle = function(ev) {
        var func;
        var use_calendar_change = dojo.byId("use_calendar_change");

        this.active = ev.target.checked;

        if (this.active) {
            func = show;
            use_calendar_change.disabled = false;
        } else {
            use_calendar_change.checked = false;
            use_calendar_change.doCommand();
            use_calendar_change.disabled = true;
            func = hide;
        }

        func("enum_editor_here");
    };

    this.compile = function() {
        if (!this.active) return [];

        var rows = dojo.mixin({}, this.normal_rows, this.alt_rows);
        var subfields = [].concat(this.normal_subfields, this.alt_subfields);

        return subfields.filter(
            function(subfield) { return Boolean(rows[subfield]); }
        ).reduce(
            function(result, subfield) {
                var fields = rows[subfield].fields;
                var pairs = [subfield, fields.caption.value];

                if (subfield != "a" && subfield != "g") {
                    if (fields.units_per.value == "number") {
                        if (fields.units_per_number.value) {
                            pairs = pairs.concat([
                                "u", fields.units_per_number.value,
                                "v", fields.continuity.value
                            ]);
                        }
                    } else {
                        pairs = pairs.concat([
                            "u", fields.units_per.value,
                            "v", fields.continuity.value
                        ]);
                    }
                }

                return result.concat(pairs);
            }, []
        );
    };

    this._init.apply(this, arguments);
}

function Wizard() {
    var self = this;

    var _step_prefix = "wizard_step_";
    var _step_regex = new RegExp("^" + _step_prefix + "(.+)$");

    this._init = function(onsubmit) {
        this._onsubmit = onsubmit;

        this.load();
        this.reset();
    };

    this.load = function() {
        /* The Wizard object will handle simpler parts of the wizard (those
         * parts with more-or-less static controls) itself, and will
         * instantiate more specific objects to deal with more dynamic
         * super-widgets (like the enum and chron editors).
         */
        this.steps = dojo.query("[id^='" + _step_prefix + "']").map(
            function(o) {
                return dojo.attr(o, "id").match(_step_regex)[1];
            }
        );

        this.enum_editor = new EnumEditor();
        this.chron_editor = new ChronEditor();
        this.calendar_change_editor = new CalendarChangeEditor();
        this.regularity_editor = new RegularityEditor();

        this.field_w = dojo.byId("hard_w");
        dojo.attr(
            dojo.byId("soft_w"), "onchange", function(ev) {
                var use_regularity = dojo.byId("use_regularity");
                if (ev.target.value && !use_regularity.checked) {
                    use_regularity.checked = true;
                    use_regularity.doCommand();
                }
            }
        );
    };

    this.reset = function() {
        this.step = 0;
        this.show_only_step(this.steps[0]);
        this.step_bounds_check();
    };

    this.show_step = function(step) { show(_step_prefix + step); }
    this.hide_step = function(step) { hide(_step_prefix + step); }

    this.step_bounds_check = function() {
        dojo.byId("wizard_previous_step").disabled = this.step < 1;
        dojo.byId("wizard_next_step").disabled =
            this.step >= this.steps.length -1;
    };

    this.show_only_step = function(to_keep) {
        this.steps.forEach(
            function(step) { if (step != to_keep) self.hide_step(step); }
        );
        this.show_step(to_keep);
    };

    this.previous_step = function() {
        this.show_only_step(this.steps[--(this.step)]);
        this.step_bounds_check();
    };

    /* Figure out the what step we're in, and proceed to the next */
    this.next_step = function() {
        this.show_only_step(this.steps[++(this.step)]);
        this.step_bounds_check();
    };

    this.frequency_type_toggle = function(which) {
        var other = which == "soft_w" ? "hard_w" : "soft_w";

        dojo.byId(other).disabled = true;
        dojo.byId(which).disabled = false;
        dojo.byId(which).focus();

        this.field_w = dojo.byId(which);
    };

    this.compile = function() {
        var code = [
            dojo.byId("ind1").value, dojo.byId("ind2").value,
            "8", "1" /* TODO find out how to best deal with $8 */
        ];

        code = code.concat(this.enum_editor.compile());
        code = code.concat(this.chron_editor.compile());

        code = code.concat("w", this.field_w.value);

        code = code.concat(this.calendar_change_editor.compile());
        code = code.concat(this.regularity_editor.compile());

        return code;
    };

    this.submit = function() {
        this._onsubmit(js2JSON(this.compile()));
        window.close();
    };

    this._init.apply(this, arguments);
}

function my_init() {
    _chronstants.week.names = S("weeks").split(".");    /* ., sic */
    _chronstants.weekday.names = S("weekdays").split(" ");
    _chronstants.month.names = S("months").split(" ");
    _chronstants.season.names = S("seasons").split(" ");

    wizard = new Wizard(window.arguments[0]);
}

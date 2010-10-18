/* The code in this file relies on common.js */

dojo.require("openils.Util");

var wizard;

function S(k) {
    return dojo.byId("serialStrings").getString("pattern_wizard." + k).
        replace("\\n", "\n");
}

function _month_menuitems() {
    /* XXX i18n, and also this is just pathetic in general, but a datepicker
     * seemed wrong since we don't want a year. */
    return [
        ["01", "January"],
        ["02", "February"],
        ["03", "March"],
        ["04", "April"],
        ["05", "May"],
        ["06", "June"],
        ["07", "July"],
        ["08", "August"],
        ["09", "September"],
        ["10", "October"],
        ["11", "November"],
        ["12", "December"]
    ].map(
        function(t) {
            return dojo.create("menuitem", {"value": t[0], "label": t[1]});
        }
    );
}

function _date_validate(date_val, month_val) {
    /* general purpose date validation irrespective of year */
    date_val = date_val.trim();

    if (!date_val.match(/^[0123]?\d$/))
        return false;

    date_val = Number(date_val); /* do NOT use parseInt */
    month_val = Number(month_val);

    if (date_val < 1) {
        return false;
    } else if (month_val == 2) {
        return date_val <= 29;
    } else if ([1,3,5,7,8,10,12].indexOf(month_val) != -1) {
        return date_val <= 31;
    } else {
        return date_val <= 30;
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

        var date_month_selector = node_by_name("date_month", this.element);

        dojo.attr(
            node_by_name("date_day", this.element), "onchange", function(ev) {
                if (_date_validate(ev.target.value,date_month_selector.value)){
                    return true;
                } else {
                    alert(S("bad_date_value"));
                    ev.target.focus();
                    return false;
                }
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
            dojo.query("[name='month'] menupopup", this.template)[0],
            dojo.query("[name='date_month'] menupopup", this.template)[0]
        ].forEach(
            function(menupopup) {
                _month_menuitems().forEach(
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

        this.field_w = dojo.byId("hard_w");
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

        return code;
    };

    this.submit = function() {
        this._onsubmit(js2JSON(this.compile()));
        window.close();
    };

    this._init.apply(this, arguments);
}

function my_init() {
    wizard = new Wizard(window.arguments[0]);
}

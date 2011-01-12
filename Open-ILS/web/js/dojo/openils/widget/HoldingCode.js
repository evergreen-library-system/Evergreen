if (!dojo._hasResource["openils.widget.HoldingCode"]) {
    dojo.provide("openils.widget.HoldingCode");
    dojo.require("dijit.layout.ContentPane");
    dojo.require("dijit.form.DropDownButton");
    dojo.require("dijit.form.TextBox");
    dojo.require("dijit.form.NumberTextBox");

    var _needed_fields = "abcdefghijklm";

    function _prepare_ttip_dialog(div, wizard) {
        dojo.empty(div);

        var selector = wizard.args.scap_selector;
        var caption_and_pattern = new scap().fromStoreItem(selector.item);

        /* we're going to look for subfields a-h and i-m now. There may already
         * be JS libs available to make this easier, but for now I'm doing this
         * the fastest way I know. */

        var pattern_code;
        try {
            pattern_code = JSON2js(caption_and_pattern.pattern_code());
        } catch (E) {
            /* no-op */;
        }

        if (!dojo.isArray(pattern_code)) {
            div.innerHTML =
                "Have you selected a valid caption and pattern?";/* XXX i18n */
            return;
        }

        var fields = [];
        for (var i = 0; i < pattern_code.length; i += 2) {
            var subfield = pattern_code[i];
            var value = pattern_code[i + 1];

            if (_needed_fields.indexOf(subfield) != -1)
                fields.push({"subfield": subfield, "caption": value});
        }

        if (!fields.length) {
            div.innerHTML = /* XXX i18n (below) */
                "No caption subfields in seleted caption and pattern";
            return;
        }

        _prepare_ttip_dialog_fields(div, fields, wizard);
    }

    function _prepare_ttip_dialog_fields(div, fields, wizard) {
        /* XXX TODO Don't assume these defaults for the indicators and $8, and
         * provide reasonable control over them. */
        var holding_code = ["4", "1", "8", "1"];
        var inputs = [];

        wizard.wizard_button.attr("disabled", true);
        var table = dojo.create("table", {"className": "serial-holding-code"});
        fields.forEach(
            function(field) {
                var tr = dojo.create("tr", null, table);

                field.caption = field.caption.replace(/^\(?([^\)]+)\)?$/, "$1");
                if (field.subfield > "h") {
                    field.caption = field.caption.slice(0,1).toUpperCase() +
                        field.caption.slice(1);
                }

                dojo.create("td", {"innerHTML": field.caption}, tr);
                var dij = field.subfield > "h" ?
                    dijit.form.NumberTextBox : dijit.form.TextBox;
                var input = new dij(
                    {
                        "name": field.subfield,
                        "constraints": {"pattern": "####"}
                    },
                    dojo.create("td", null, tr)
                );
                input.startup();
                wizard.preset_input_by_date(input, field.caption.toLowerCase());
                inputs.push({"subfield": field.subfield, "input": input});
            }
        );

        new dijit.form.Button(
            {
                "label": "Compile",
                "onClick": function() {
                    inputs.forEach(
                        function(input) {
                            var value = input.input.attr("value");
                            if (value === null || isNaN(value)) {
                                /* XXX i18n */
                                alert("A valid holding code cannot be " +
                                    "produced with any blank fields.");
                            }
                            holding_code.push(input.subfield);
                            holding_code.push(value);
                        }
                    );
                    wizard.code_text_box.attr("value", js2JSON(holding_code));
                    wizard.wizard_button.attr("disabled", false);
                    dojo.empty(div);
                }
            }, dojo.create(
                "span", null, dojo.create(
                    "td", {"colspan": 2},
                    dojo.create("tr", null, table)
                )
            )
        );
        dojo.place(table, div, "only");
    }

    /* Approximate a season value given a date using the same logic as
     * OpenILS::Utils::MFHD::Holding::chron_to_date().
     */
    function _loose_season(D) {
        var m = D.getMonth() + 1;
        var d = D.getDate();

        if (
            (m == 1 || m == 2) || (m == 12 && d >= 21) || (m == 3 && d < 20)
        ) {
            return 24;  /* MFHD winter */
        } else if (
            (m == 4 || m == 5) || (m == 3 && d >= 20) || (m == 6 && d < 21)
        ) {
            return 21;  /* spring */
        } else if (
            (m == 7 || m == 8) || (m == 6 && d >= 21) || (m == 9 && d < 22)
        ) {
            return 22;  /* summer */
        } else {
            return 23;  /* autumn */
        }
    }

    dojo.declare(
        "openils.widget.HoldingCode", dijit.layout.ContentPane, {
            "constructor": function(args) {
                this.args = args || {};
            },

            "startup": function() {
                var self = this;
                this.inherited(arguments);

                var dialog_div = dojo.create(
                    "div", {
                        "style": "padding:1em;margin:0;text-align:center;"
                    }, this.domNode
                );
                var target_div = dojo.create("div", null, this.domNode);
                dojo.create("br", null, this.domNode);

                this.wizard_button = new dijit.form.Button(
                    {
                        "label": "Wizard" /* XXX i18n */,
                        "onClick": function() {
                            _prepare_ttip_dialog(target_div, self);
                        }
                    },
                    dojo.create("span", null, dialog_div)
                );

                this.code_text_box = new dijit.form.TextBox(
                    {}, dojo.create("div", null, this.domNode)
                );
                this.code_text_box.startup();
            },

            "attr": function(name, value) {
                if (name == "value") {
                    /* XXX can this get called before any subdijits are
                     * built (before startup() is run)? */
                    if (value) {
                        this.code_text_box.attr(name, value);
                    }
                    return this.code_text_box.attr(name);
                } else {
                    return this.inherited(arguments);
                }
            },

            "update_scap_selector": function(selector) {
                this.args.scap_selector = selector;
                this.attr("value", "");
            },

            "preset_input_by_date": function(input, chron_part) {
                try {
                    input.attr("value", {
                            /* NOTE: week is specifically not covered. I'm
                             * not sure there's an acceptably standard way
                             * to number the weeks in a year.  Do we count
                             * from the week of January 1? Or the first week
                             * with a day of the week matching our example
                             * date?  Do weeks run Mon-Sun or Sun-Sat?
                             */
                            "year": function(d) { return d.getFullYear(); },
                            "season": function(d) { return _loose_season(d); },
                            "month": function(d) { return d.getMonth() + 1; },
                            "day": function(d) { return d.getDate(); },
                            "hour": function(d) { return d.getHours(); },
                        }[chron_part](this.date_widget.attr("value"))
                    );
                } catch (E) {
                    ; /* Oh well; can't win them all. */
                }
            },

            "date_widget": null
        }
    );
}

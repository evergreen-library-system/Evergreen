if (!dojo._hasResource['openils.widget.PCrudFilterPane']) {

    /* openils.widget.PCrudFilterPane is a dijit that, given a fieldmapper
     * class, provides a pane in which users can define inclusionary
     * filters based on fields selected from the fieldmapper class and values
     * for those fields.  Operators can be selected so that not only equality
     * comparisons are possible in the filter, but also inequality filters,
     * likeness (for text fields only) betweenness, and nullity tests.  *
     * The dijit yields its result in the form of a JSON query suitable for
     * use as the where clause of a pcrud search, via the onApply callback.
     *
     * In addition to its fmClass paramter, note the useful parameter
     * suppressFilterFields.  Say for instance you're using this dijit
     * on an fmClass like "brt" which has a field "record" that points to the
     * bre class.  The AutoWidget provided for users to enter values for
     * comparisons on the record field would be a dropdown containing all
     * the bre ID's in the system!  That would be unusable in any realistic
     * system, unless/until we teach AutoWidget to use a lazy-loading store
     * for dropdowns.
     *
     * The comparisons in each filter row are "and-ed" together in the JSON
     * query yielded, except for repetitions of the same field, which are
     * "or-ed" together /within/ the overall "and" group.  Look at comments
     * within PCrudFilterRowManager.compile() for more information.
     *
     * AutoGrid has some ability to use this dijits based on this to offer a
     * filtering dialog, but be aware that the filtering dialog is /not/ aware
     * of other fitering measures in place in a given AutoGrid-based interface,
     * such as (typically) context org unit selectors, and therefore using the
     * context org unit selector will not respect selected filters in this
     * dijit, and vice-versa.
     */

    dojo.provide('openils.widget.PCrudFilterPane');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('dijit.form.FilteringSelect');
    dojo.require('dijit.form.Button');
    dojo.require('dijit.form.DropDownButton');
    dojo.require('dijit.TooltipDialog');
    dojo.require('dojo.data.ItemFileReadStore');
    dojo.require('openils.Util');

    dojo.requireLocalization("openils.widget", "PCrudFilterPane");

    var pcFilterLocaleStrings = dojo.i18n.getLocalization(
        "openils.widget", "PCrudFilterPane"
    );

    /* These are the operators that make up the central dropdown in each
     * row of the widget.  When fields of different datatypes are selected,
     * some of these operators may be masked via the "minimal" and "strict"
     * properties.
     */
    var _operator_store = new dojo.data.ItemFileReadStore(
        {
            "data": {
                "identifier": "name",
                "items": [
                    {
                        "name": "=",
                        "label": pcFilterLocaleStrings.OPERATOR_EQ,
                        "param_count": 1,
                        "minimal": true,
                        "strict": true
                    }, {
                        "name": "!=",
                        "label": pcFilterLocaleStrings.OPERATOR_NE,
                        "param_count": 1,
                        "minimal": true,
                        "strict": true
                    }, {
                        "name": "null",
                        "label": pcFilterLocaleStrings.OPERATOR_IS_NULL,
                        "param_count": 0,
                        "minimal": true,
                        "strict": true
                    }, {
                        "name": "not null",
                        "label": pcFilterLocaleStrings.OPERATOR_IS_NOT_NULL,
                        "param_count": 0,
                        "minimal": true,
                        "strict": true
                    }, {
                        "name": ">",
                        "label": pcFilterLocaleStrings.OPERATOR_GT,
                        "param_count": 1,
                        "strict": true
                    }, {
                        "name": "<",
                        "label": pcFilterLocaleStrings.OPERATOR_LT,
                        "param_count": 1,
                        "strict": true
                    }, {
                        "name": ">=",
                        "label": pcFilterLocaleStrings.OPERATOR_GTE,
                        "param_count": 1,
                        "strict": true
                    }, {
                        "name": "<=",
                        "label": pcFilterLocaleStrings.OPERATOR_LTE,
                        "param_count": 1,
                        "strict": true
                    }, {
                        "name": "in",
                        "label": pcFilterLocaleStrings.OPERATOR_IN,
                        "param_count": null,    /* arbitrary number, special */
                        "strict": true,
                        "minimal": true
                    }, {
                        "name": "not in",
                        "label": pcFilterLocaleStrings.OPERATOR_NOT_IN,
                        "param_count": null,    /* arbitrary number, special */
                        "strict": true,
                        "minimal": true
                    }, {
                        "name": "between",
                        "label": pcFilterLocaleStrings.OPERATOR_BETWEEN,
                        "param_count": 2,
                        "strict": true
                    }, {
                        "name": "not between",
                        "label": pcFilterLocaleStrings.OPERATOR_NOT_BETWEEN,
                        "param_count": 2,
                        "strict": true
                    }, {
                        "name": "like",
                        "label": pcFilterLocaleStrings.OPERATOR_LIKE,
                        "param_count": 1
                    }, {
                        "name": "not like",
                        "label": pcFilterLocaleStrings.OPERATOR_NOT_LIKE,
                        "param_count": 1
                    }
                ]
            }
        }
    );

    /* The text datatype supports all the above operators for comparisons. */
    var _store_query_by_datatype = {"text": {}};

    /* These three datatypes support only minimal operators. */
    ["bool", "link", "org_unit"].forEach(
        function(type) {
            _store_query_by_datatype[type] = {"minimal": true};
        }
    );

    /* These datatypes support strict operators (everything save [not] like). */
    ["float", "id", "int", "interval", "money", "number", "timestamp"].forEach(
        function(type) {
            _store_query_by_datatype[type] = {"strict": true};
        }
    );

    /* This helps convert things that pcrud won't accept ("not between", "not
     * like") into proper JSON query expressions.
     * It returns false if a clause doesn't have any such negative operator,
     * or it returns true AND gets rid of the "not " part in the clause
     * object itself.  It's up to the caller to wrap it in {"-not": {}} in
     * the right place. */
    function _clause_was_negative(clause) {
        /* clause objects really only ever have one property */
        if (clause === null) return false; /* early out for special operator */

        var ops = openils.Util.objectProperties(clause);
        var op = ops.pop();
        var matches = op.match(/^(not) ([lb].+)$/); /* "not in" needs no change */
        if (matches) {
            clause[matches[2]] = clause[op];
            delete clause[op];
            return true;
        }
        return false;
    }

    /* Given a value, add it to selector options if it's not already there,
     * and select it. */
    function _add_or_at_least_select(value, selector) {
        var found = false;

        for (var i = 0; i < selector.options.length; i++) {
            var option = selector.options[i];
            if (option.value == value) {
                found = true;
                option.selected = true;
            }
        }

        if (!found) {
            dojo.create(
                "option", {
                    "innerHTML": value,
                    "value": value,
                    "selected": "selected"
                }, selector
            );
        }
    }

    /* This is not the dijit per se. Search further in this file for
     * "dojo.declare" for the beginning of the dijit.
     *
     * This is, however, the object that represents a collection of filter
     * rows and knows how to compile a filter from those rows. */
    function PCrudFilterRowManager() {
        var self = this;

        this._init = function(
            container, field_store, fm_class, compact, widget_builders,
            skip_first_add_row, do_apply
        ) {
            this.container = container;
            this.field_store = field_store;
            this.fm_class = fm_class;
            this.compact = compact;
            this.widget_builders = widget_builders || {};
            this.skip_first_add_row = skip_first_add_row;
            this.do_apply = do_apply;

            this.rows = {};
            this.row_index = 0;

            this._build_table();
        };

        this._build_table = function() {
            this.table = dojo.create(
                "table", {
                    "className": "oils-pcrudfilterdialog-table"
                }, this.container
            );

            var tr = dojo.create(
                "tr", {
                    "id": "pcrudfilterdialog-empty",
                    "className": "hidden"
                }, this.table
            );

            dojo.create(
                "td", {
                    "colspan": 4,
                    "innerHTML": pcFilterLocaleStrings[
                        this.compact ? "EMPTY_CASE_COMPACT" : "EMPTY_CASE"
                    ]
                }, tr
            );

            if (!this.skip_first_add_row)
                this.add_row();
        };

        this._compile_second_pass = function(first_pass) {
            var and = [];
            var result = {"-and": and};

            for (var field in first_pass) {
                var list = first_pass[field];
                if (list.length == 1) {
                    var obj = {};
                    var clause = list.pop();
                    if (_clause_was_negative(clause)) {
                        obj["-not"] = {};
                        obj["-not"][field] = clause;
                    } else {
                        obj[field] = clause;
                    }
                    and.push(obj);
                } else {
                    var or = list.map(
                        function(clause) {
                            var obj = {};
                            if (_clause_was_negative(clause)) {
                                obj["-not"] = {};
                                obj["-not"][field] = clause;
                            } else {
                                obj[field] = clause;
                            }
                            return obj;
                        }
                    );
                    and.push({"-or": or});
                }
            }

            return result;
        };

        this._validate_initializer = function(initializer, onsuccess) {
            this.field_store.fetchItemByIdentity({
                "identity": initializer.field,
                "onItem": dojo.hitch(this, function(item) {
                    if (item) {
                        onsuccess();
                    } else {
                        console.debug(
                            "skipping initializer for field " +
                            initializer.field + " not present here"
                        );
                    }
                })
            });
        };

        this._proceed_add_row = function(initializer) {
            var row_id_list = openils.Util.objectProperties(this.rows);

            /* Kill initial empty row when adding pre-initialized rows. */
            if (row_id_list.length == 1 && initializer) {
                var existing_row_id = row_id_list.shift();
                if (this.rows[existing_row_id].is_unset())
                    this.remove_row(existing_row_id, true /* no_apply */);
            }

            this.hide_empty_placeholder();
            var row_id = this.row_index++;
            this.rows[row_id] = new PCrudFilterRow(this, row_id, initializer);
        };

        this.add_row = function(initializer) {
            if (initializer) {
                this._validate_initializer(
                    initializer,
                    dojo.hitch(this, function() {
                        this._proceed_add_row(initializer);
                    })
                );
            } else {
                this._proceed_add_row(initializer);
            }
        };

        this.remove_row = function(row_id, no_apply) {
            this.rows[row_id].destroy();
            delete this.rows[row_id];

            if (openils.Util.objectProperties(this.rows).length < 1)
                this.show_empty_placeholder();

            if (this.compact && !no_apply)
                this.do_apply();
        };

        this.hide_empty_placeholder = function() {
            openils.Util.hide("pcrudfilterdialog-empty");
        };

        this.show_empty_placeholder = function() {
            openils.Util.show("pcrudfilterdialog-empty");
        };

        this.compile = function() {
            /* We'll prepare a first-pass data structure that looks like:
             * {
             *  field1: [{"op": "one value"}],
             *  field2: [{"op": "a value"}, {"op": "b value"}],
             *  field3: [{"op": "first value"}, {"op": ["range start", "range end"]}]
             * }
             *
             * which will be passed to _compile_second_pass() to yield an
             * actual filter suitable for pcrud (with -and and -or in all the
             * right places) so the above example would come out like:
             *
             * { "-and": [
             *   {"field1": {"op": "one value"}},
             *   {"-or": [ {"field2": {"op": "a value"}}, {"field2": {"op": "b value"}} ] },
             *   {"-or": [
             *     {"field3": {"op": "first value"}},
             *     {"field3": {"op": ["range start", "range end"]}}
             *   ] }
             * ] }
             */
            var first_pass = {};

            for (var row_id in this.rows) {
                var row = this.rows[row_id];
                var value = row.compile();
                var field = row.selected_field;

                if (typeof(value) != "undefined" &&
                    typeof(field) != "undefined") {
                    if (!first_pass[field])
                        first_pass[field] = [];
                    first_pass[field].push(value);
                }
            }

            /* Don't return an empty filter: pcrud can't use that. */
            if (openils.Util.objectProperties(first_pass).length < 1) {
                var result = {};
                result[fieldmapper[this.fm_class].Identifier] = {"!=": null};
                return result;
            } else {
                return this._compile_second_pass(first_pass);
            }
        };

        /* This is for generating a data structure so that we can store
         * a representation of the state of the filter rows.  Not for
         * generating a query to be used in search.  You want compile() for
         * that. */
        this.serialize = function() {
            var serialized = [];
            for (var rowkey in this.rows) { /* row order doesn't matter */
                var row_ser = this.rows[rowkey].serialize();
                if (row_ser)
                    serialized.push(row_ser);
            }
            return dojo.toJson(serialized);
        };

        this._init.apply(this, arguments);
    }

    /* As the name implies, objects of this class manage a single row of the
     * query.  Therefore they know about their own field dropdown, their own
     * selector dropdown, and their own value widget (or widgets in the case
     * of between searches, which call for two widgets to define a range),
     * and not much else. */
    function PCrudFilterRow() {
        var self = this;

        this._init = function(filter_row_manager, row_id, initializer) {
            this.filter_row_manager = filter_row_manager;
            this.row_id = row_id;

            if (this.filter_row_manager.compact)
                this._build_compact();
            else
                this._build();

            if (initializer)
                this.initialize(initializer);
        };

        this._build = function() {
            this.tr = dojo.create("tr", {}, this.filter_row_manager.table);

            this._create_field_selector();
            this._create_operator_selector();
            this._create_value_slot();
            this._create_remover();
        };

        this._build_compact = function() {
            this.tr = dojo.create("tr", {}, this.filter_row_manager.table);

            var td = dojo.create("td", {}, this.tr);

            this._create_field_selector(td);
            this._create_operator_selector(td);

            dojo.create("br", {}, td);
            this._create_value_slot(td);

            td = dojo.create(
                "td",
                {"className": "oils-pcrudfilterdialog-remover-holder"},
                this.tr
            );

            this._create_remover(td);
        };

        this._create_field_selector = function(use_element) {
            var td = use_element || dojo.create("td", {}, this.tr);

            this.field_selector = new dijit.form.FilteringSelect(
                {
                    "labelAttr": "label",
                    "searchAttr": "label",
                    "scrollOnFocus": false,
                    "onChange": function(value) {
                        self.update_selected_field(value);
                        if (this.and_then) {    /* ugh. also, self != this. */
                            var once = this.and_then;
                            delete this.and_then;
                            once();
                        }
                    },
                    "store": this.filter_row_manager.field_store
                }, dojo.create("span", {}, td)
            );
        };

        this._create_operator_selector = function(use_element) {
            var td = use_element || dojo.create("td", {}, this.tr);

            this.operator_selector = new dijit.form.FilteringSelect(
                {
                    "labelAttr": "label",
                    "searchAttr": "label",
                    "scrollOnFocus": false,
                    "onChange": function(value) {
                        self.update_selected_operator(value);
                    },
                    "store": _operator_store
                }, dojo.create("span", {}, td)
            );
        };

        this._adjust_operator_selector = function() {
            this.operator_selector.attr(
                "query", _store_query_by_datatype[this.selected_field_type]
            );
            this.operator_selector.reset();
        };

        this._create_value_slot = function(use_element) {
            var how = {"innerHTML": "-"};

            if (use_element)
                this.value_slot = dojo.create("span", how, use_element);
            else
                this.value_slot = dojo.create("td", how, this.tr);
        };

        this._create_remover = function(use_element) {
            var td = use_element || dojo.create("td", {}, this.tr);
            var anchor = dojo.create(
                "a", {
                    "className": "oils-pcrudfilterdialog-remover",
                    "innerHTML": "X",
                    "href": "#",
                    "onclick": function() {
                        self.filter_row_manager.remove_row(self.row_id);
                    }
                }, td
            );
        };

        this._clear_value_slot = function() {
            var old_widget_values = [];
            if (this.value_widgets) {
                this.value_widgets.forEach(
                    function(autowidg) {
                        if (autowidg.widget) {
                            old_widget_values.push({'value' : autowidg.widget.attr("value"),
                                                    'type' : autowidg.widget.attr("type") });
                            autowidg.widget.destroy();
                        }
                    }
                );
                delete this.value_widgets;
            }
            this.old_widget_values = old_widget_values;

            dojo.empty(this.value_slot);
        };

        this._rebuild_value_widgets = function() {
            this._clear_value_slot();

            if (!this.get_selected_operator() || !this.selected_field)
                return;

            this.value_widgets = [];

            /* This is where find custom widget builders to deploy shortly. */
            var widget_builder_key = this.selected_field_fm_class + ":" +
                this.selected_field_fm_field;
            var constr =
                this.filter_row_manager.widget_builders[widget_builder_key] ||
                openils.widget.AutoFieldWidget;

            /* How many value widgets do we need for this operator? */
            var param_count =
                this.operator_selector.store.getValue(
                    this.operator_selector.item, "param_count"
                );

            if (param_count === null) {
                /* When param_count is null, we invoke the special case of
                 * preparing widgets for building a dynamic set of values.
                 * All other cases are handled by the else branch. */
                this._build_set_value_widgets(constr);
            } else {
                for (var i = 0; i < param_count; i++) {
                    this.value_widgets.push(
                        this._build_one_value_widget(constr)
                    );
                    if (typeof this.old_widget_values != "undefined" &&
                        typeof this.old_widget_values[i] != "undefined" &&
                        this.value_widgets[i].widget.attr("type") == this.old_widget_values[i].type) {
                        this.value_widgets[i].widget.attr("value", this.old_widget_values[i].value);
                    }
                }
            }
            delete this.old_widget_values;
        };

        this._build_set_value_widgets = function(constr) {
            var value_widget = dojo.create(
                "select", {
                    "multiple": "multiple",
                    "size": 4,
                    "style": {
                        "width": "6em",
                        "verticalAlign": "middle",
                        "margin": "0 0.75em"
                    }
                },
                this.value_slot
            );
            var entry_widget = this._build_one_value_widget(constr);
            var adder = dojo.create(
                "a", {
                    "href": "javascript:void(0);",
                    "style": {"verticalAlign": "middle", "margin": "0 0.75em"},
                    "innerHTML": "[+]", /* XXX i18n? */
                    "onclick": dojo.hitch(this, function() {
                        _add_or_at_least_select(
                            this._value_for_compile(entry_widget),
                            value_widget
                        );
                        entry_widget.widget.attr("value", ""); /* clear */
                    })
                }, this.value_slot
            );
            this.value_widgets.push(value_widget);
        };


        /* Create just one value widget (used by higher-level functions
         * that worry about how many are needed). */
        this._build_one_value_widget = function(constr) {
            var widg = new constr({
                "fmClass": this.selected_field_fm_class,
                "fmField": this.selected_field_fm_field,
                "noDisablePkey": true,
                "parentNode": dojo.create(
                    "span", {
                        "style": {"verticalAlign": "middle"}
                    }, this.value_slot
                ),
                "dijitArgs": {"scrollOnFocus": false}
            });

            widg.build();
            return widg;
        };

        this._value_for_serialize = function(widg) {
            if (!widg.widget)   /* widg is <select> */
                return dojo.filter(
                    widg.options,
                    function(o) { return o.selected; }
                ).map(
                    function(o) { return o.value; }
                );
            else
                return widg.widget.attr("value");
        };

        this._value_for_compile = function(widg) {
            if (!widg.widget)   /* widg is <select> */
                return dojo.filter(
                    widg.options,
                    function(o) { return o.selected; }
                ).map(
                    function(o) { return o.value; }
                );
            else if (widg.useCorrectly)
                return widg.widget.attr("value");
            else if (this.selected_field_is_indirect)
                return widg.widget.attr("displayedValue");
            else
                return widg.getFormattedValue();
        }

        /* for ugly special cases in compilation */
        this._null_clause = function() {
            var opname = this.get_selected_operator_name();
            if (opname == "not null")
                return {"!=": null};
            else if (opname == "null")
                return null;
            else
                return;
        };

        /* wrap s in %'s unless it already contains at least one %. */
        this._add_like_wildcards = function(s) {
            return s.indexOf("%") == -1 ? ("%" + s + "%") : s;
        };

        this.get_selected_operator = function() {
            if (this.operator_selector)
                return this.operator_selector.item;
        };

        this.get_selected_operator_name = function() {
            var item = this.get_selected_operator();
            if (item) {
                return this.operator_selector.store.getValue(item, "name");
            } else {
                console.warn(
                    "Could not determine selected operator. " +
                    "Something is about to break."
                );
            }
        };

        this.update_selected_operator = function(value) {
            this._rebuild_value_widgets();
        };

        this.update_selected_field = function(value) {
            if (this.field_selector.item) {
                this.selected_field = value;
                this.selected_field_type = this.field_selector.item.type;

                /* This is really about supporting flattenergrid, of which
                 * we're in the superclass (in a sloppy sad way). From now
                 * on I won't mix this kind of lazy object with Dojo modules. */
                this.selected_field_fm_field = this.field_selector.item.name;
                this.selected_field_is_indirect =
                    this.field_selector.item.indirect || false;
                this.selected_field_fm_class =
                    this.field_selector.item.fmClass ||
                    this.filter_row_manager.fm_class;

                this._adjust_operator_selector();
                this._rebuild_value_widgets();
            }
        };

        this.serialize = function() {
            if (!this.selected_field)
                return;

            var serialized = {
                "field": this.selected_field,
                "operator": this.get_selected_operator_name()
            };

            var values;

            if (this.value_widgets) {
                values = this.value_widgets.map(
                    dojo.hitch(
                        this, function(w) {
                            return this._value_for_serialize(w);
                        }
                    )
                );
            }

            /* The following grew organically to be very silly and confusing.
             * Could use a rethink (PCrudFilterRow.initialize() would also need
             * matching changes). */
            if (values.length == 1) {
                if (dojo.isArray(values[0]))
                    serialized.values = values[0];
                else
                    serialized.value = values[0];
            } else if (values.length > 1) {
                serialized.values = values;
            }

            return serialized;
        };

        this.compile = function() {
            if (this.value_widgets) {
                var values = this.value_widgets.map(
                    dojo.hitch(this, this._value_for_compile)
                );

                if (!values.length) {
                    return this._null_clause(); /* null/not null */
                } else {
                    var clause = {};
                    var op = this.get_selected_operator_name();

                    var prep_function = function(o) {
                        if (dojo.isArray(o) && !o.length)
                            throw new Error(pcFilterLocaleStrings.EMPTY_LIST);

                        return o;
                    };

                    if (String(op).match(/like/))
                        prep_function = this._add_like_wildcards;

                    if (values.length == 1)
                        clause[op] = prep_function(values.pop());
                    else
                        clause[op] = dojo.map(values, prep_function);
                    return clause;
                }
            } else {
                return;
            }
        };

        this.destroy = function() {
            this._clear_value_slot();
            this.field_selector.destroy();
            if (this.operator_selector)
                this.operator_selector.destroy();

            dojo.destroy(this.tr);
        };

        this.initialize = function(initializer) {
            /* and_then is a nasty kludge callback called once at onChange */
            this.field_selector.and_then = dojo.hitch(
                this, function() {
                    this.operator_selector.attr("value", initializer.operator);

                    /* Caller supplies value for one value, values (array) for
                     * multiple. */
                    if (typeof initializer.value !== "undefined" &&
                            !initializer.values) {
                        initializer.values = [initializer.value];
                    }
                    initializer.values = initializer.values || [];

                    if (initializer.operator.match(/^(not ?)in$/)) {
                        /* "in" and "not in" need special treatement */
                        dojo.forEach(
                            initializer.values, dojo.hitch(this, function(v) {
                                _add_or_at_least_select(
                                    v, this.value_widgets[0]
                                );
                            })
                        );
                    } else {
                        /* other operators work this way: */
                        for (var i = 0; i < initializer.values.length; i++) {
                            this.value_widgets[i].widget.attr(
                                "value", initializer.values[i]
                            );
                        }
                    }
                }
            );
            this.field_selector.attr("value", initializer.field);
        };

        this.is_unset = function() {
            return !Boolean(this.field_selector.attr("value"));
        };

        this._init.apply(this, arguments);
    }

    dojo.declare(
        "openils.widget.PCrudFilterPane", [openils.widget.AutoWidget],
        {
            "useDiv": null, /* should always be null for subclass dialogs */
            "initializers": null,
            "widgetBuilders": null,
            "suppressFilterFields": null,
            "savedFiltersInterface": null,

            "constructor": function(args) {
                for(var k in args)
                    this[k] = args[k];
                this.widgetIndex = 0;
                this.widgetCache = {};
                this.compact = Boolean(this.useDiv);

                /* Meaningless in a pane, but better here than in
                 * PCrudFilterDialog so that we don't need to load i18n
                 * strings there: */
                this.title = this.title || pcFilterLocaleStrings.DEFAULT_DIALOG_TITLE;
            },

            "_buildSavedFilterControlsIfPerms": function(holder) {
                (new openils.User()).getPermOrgList(
                    "SAVED_FILTER_DIALOG_FILTERS",
                    dojo.hitch(this, function(id_list) {
                        this._buildSavedFilterControls(id_list, holder);
                    }),
                    true, true
                );
            },

            "_buildSavedFilterControls": function(id_list, holder) {
                if (!id_list || !id_list.length) {
                    console.info("Not showing saved filter controls; no perm");
                    return;
                }

                var fs_list = (new openils.PermaCrud()).search(
                    "cfdfs", {
                        "owning_lib": id_list,
                        "interface": this.savedFiltersInterface
                    }, {
                        "order_by": [
                            {"class": "cfdfs", "field": "owning_lib"},
                            {"class": "cfdfs", "field": "name"}
                        ],
                        "async": true,
                        "oncomplete": dojo.hitch(this, function(r) {
                            if (r = openils.Util.readResponse(r)) {
                                this._buildSavedFilterLoader(r, holder);
                            }
                        })
                    }
                );

                this._buildSavedFilterSaver(holder);
            },

            "_buildSavedFilterLoader": function(fs_list, holder) {
                var self = this;
                var load_content = dojo.create(
                    "div", {
                        "innerHTML": pcFilterLocaleStrings.CHOOSE_FILTER_TO_LOAD
                    }
                );

                var selector = dojo.create(
                    "select", {
                        "multiple": "multiple",
                        "size": 4,
                        "style": {
                            "verticalAlign": "middle", "margin": "0 0.75em"
                        }
                    }, load_content, "last"
                );

                dojo.forEach(
                    fs_list, function(fs) {
                        dojo.create(
                            "option", {
                                "innerHTML": fs.name(),
                                "value": dojo.toJson([fs.id(),
                                    dojo.fromJson(fs.filters())])
                            }, selector
                        );
                    }
                );

                var applicator = dojo.create(
                    "a", {
                        "href": "javascript:void(0);",
                        "onclick": function() {
                            dojo.filter(
                                selector.options,
                                function(o){return o.selected;}
                            ).map(
                                function(o){return dojo.fromJson(o.value)[1];}
                            ).forEach(
                                function(o){
                                    o.forEach(
                                        function(p) {
                                            self.filter_row_manager.add_row(p);
                                        }
                                    );
                                }
                            );
                            dijit.popup.close(self.filter_set_loader.dropDown);
                        },
                        "innerHTML": pcFilterLocaleStrings.APPLY
                    }, load_content, "last"
                );

                this.filter_set_loader = new dijit.form.DropDownButton({
                    "dropDown": new dijit.TooltipDialog({
                        "content": load_content
                    }),
                    "label": pcFilterLocaleStrings.LOAD_FILTERS
                }, dojo.create("span", {}, holder));
            },

            "_buildSavedFilterSaver": function(holder) {
                this.filter_set_loader = new dijit.form.Button({
                    "onClick": dojo.hitch(
                        this, function() {
                            this.saveFilters(
                                /* XXX I know some find prompt() objectionable
                                 * somehow, but I can't seem to type into any
                                 * text inputs that I put inside TooltipDialog
                                 * instances, so meh. */
                                prompt(
                                    pcFilterLocaleStrings.NAME_SAVED_FILTER_SET
                                )
                            );
                        }
                    ),
                    "label": pcFilterLocaleStrings.SAVE_FILTERS
                }, dojo.create("span", {}, holder));
            },

            "_buildButtons": function() {
                var self = this;

                var button_holder = dojo.create(
                    "div", {
                        "className": "oils-pcrudfilterdialog-buttonholder"
                    }, this.domNode
                );

                new dijit.form.Button(
                    {
                        "label": pcFilterLocaleStrings.ADD_ROW,
                        "scrollOnFocus": false, /* almost always better */
                        "onClick": function() {
                            self.filter_row_manager.add_row();
                        }
                    }, dojo.create("span", {}, button_holder)
                );

                this._apply_button = new dijit.form.Button(
                    {
                        "label": pcFilterLocaleStrings.APPLY,
                        "scrollOnFocus": false,
                        "onClick": function() { self.doApply(); }
                    }, dojo.create("span", {}, button_holder)
                );

                if (!this.useDiv) {
                    new dijit.form.Button(
                        {
                            "label": pcFilterLocaleStrings.CANCEL,
                            "scrollOnFocus": false,
                            "onClick": function() {
                                if (self.onCancel)
                                    self.onCancel();
                                self.hide();
                            }
                        }, dojo.create("span", {}, button_holder)
                    );
                }

                if (this.savedFiltersInterface)
                    this._buildSavedFilterControlsIfPerms(button_holder);
            },

            "_buildFieldStore": function() {
                var self = this;
                var realFieldList = this.sortedFieldList.filter(
                    function(item) { return !(item.virtual || item.nonIdl); }
                );

                /* Prevent any explicitly unwanted fields from being available
                 * in our field dropdowns. */
                if (dojo.isArray(this.suppressFilterFields)) {
                    realFieldList = realFieldList.filter(
                        function(item) {
                            for (
                                var i = 0;
                                i < self.suppressFilterFields.length;
                                i++
                            ) {
                                if (item.name == self.suppressFilterFields[i])
                                    return false;
                            }
                            return true;
                        }
                    );
                }

                this.fieldStore = new dojo.data.ItemFileReadStore({
                    "data": {
                        "identifier": "name",
                        "name": "label",
                        "items": realFieldList.map(
                            function(item) {
                                return {
                                    "label": item.label,
                                    "name": item.name,
                                    "type": item.datatype
                                };
                            }
                        )
                    }
                });
            },

            "saveFilters": function(name, oncomplete) {
                var filters_value = this.filter_row_manager.serialize();
                var filter_set = new cfdfs();
                filter_set.name(name);
                filter_set.interface(this.savedFiltersInterface);
                filter_set.owning_lib(openils.User.user.ws_ou());
                filter_set.creator(openils.User.user.id()); /* not reliable */
                filter_set.filters(filters_value);

                (new openils.PermaCrud()).create(
                    filter_set, {
                        "oncomplete": dojo.hitch(this, function() {
                            var selector = dojo.query(
                                "select[multiple]",
                                this.filter_set_loader.dropDown.domNode
                            )[0];
                            dojo.create(
                                "option", {
                                    "innerHTML": name,
                                    "value": dojo.toJson([-1,
                                        dojo.fromJson(filters_value)])
                                }, selector
                            );
                            if (oncomplete) oncomplete();
                        })
                    }
                );
            },

            "hide": function() {
                try {
                    this.inherited(arguments);
                } catch (E) {
                    /* When using *FilterPane directly (without a *Dialog
                     * subclass), do nothing.  */
                    void(0);
                }
            },

            /* All we really do here is create a data store out of the fields
             * from the IDL for our given class, place a few buttons at the
             * bottom of the dialog, and hand off to PCrudFilterRowManager to
             * do the actual work.
             */

            "startup": function() {
                if (this.useDiv)
                    this.domNode = this.useDiv;

                try {
                    this.inherited(arguments);
                } catch (E) {
                    /* When using *FilterPane directly (without a *Dialog
                     * subclass), there is no startup method in any ancestor
                     * class. XXX Refactor?
                     */
                    void(0);
                }

                this.initAutoEnv();

                this._buildFieldStore();

                this.filter_row_manager = new PCrudFilterRowManager(
                    dojo.create("div", {}, this.domNode),
                    this.fieldStore, this.fmClass, this.compact,
                    this.widgetBuilders,
                    Boolean(this.initializers)  /* avoid adding empty row */,
                    dojo.hitch(this, function() { this.doApply(); })
                );

                this._buildButtons();

                if (this.initializers) {
                    this.initializers.forEach(
                        dojo.hitch(this, function(initializer) {
                            this.filter_row_manager.add_row(initializer);
                        })
                    );
                }
            },

            /* This should just be named 'apply', but that is kind of a special
             * word in Javascript, no? */
            "doApply": function() {
                this._apply_button.attr("disabled", true);

                var _E; /* Try pretty hard not to leave the apply button
                           disabled forever, even if 'apply' blows up. */
                try {
                    if (this.onApply)
                        this.onApply(this.filter_row_manager.compile());
                } catch (E) {
                    _E = E;
                }
                this.hide();
                this._apply_button.attr("disabled", false);

                if (_E) throw _E;
            }
        }
    );
}

if (!dojo._hasResource['openils.widget.PCrudFilterDialog']) {

    /* openils.widget.PCrudFilterDialog is a dijit that, given a fieldmapper
     * class, provides a dialog in which users can define inclusionary
     * filters based on fields selected from the fieldmapper class and values
     * for those fields.  Operators can be selected so that not only equality
     * comparisons are possible in the filter, but also inequality filters,
     * likeness (for text fields only) betweenness, and nullity tests.
     *
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
     * AutoGrid has some ability to use this dijit to offer a filtering dialog,
     * but be aware that the filtering dialog is /not/ aware of other
     * fitering measures in place in a given AutoGrid-based interface, such as
     * (typically) context org unit selectors, and therefore using the context
     * org unit selector will not respect selected filters in this dijit, and
     * vice-versa.
     */

    dojo.provide('openils.widget.PCrudFilterDialog');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('dijit.form.FilteringSelect');
    dojo.require('dijit.form.Button');
    dojo.require('dojo.data.ItemFileReadStore');
    dojo.require('dijit.Dialog');
    dojo.require('openils.Util');

    dojo.requireLocalization("openils.widget", "PCrudFilterDialog");

    var pcFilterLocaleStrings = dojo.i18n.getLocalization(
        "openils.widget", "PCrudFilterDialog"
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
        var ops = openils.Util.objectProperties(clause);
        var op = ops.pop();
        var matches = op.match(/^not (\w+)$/);
        if (matches) {
            clause[matches[1]] = clause[op];
            delete clause[op];
            return true;
        }
        return false;
    }

    /* This is not the dijit per se. Search further in this file for
     * "dojo.declare" for the beginning of the dijit.
     *
     * This is, however, the object that represents a collection of filter
     * rows and knows how to compile a filter from those rows. */
    function PCrudFilterRowManager() {
        var self = this;

        this._init = function(container, field_store, fm_class) {
            this.container = container;
            this.field_store = field_store;
            this.fm_class = fm_class;

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
                    "innerHTML": pcFilterLocaleStrings.EMPTY_CASE
                }, tr
            );

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

        this.add_row = function() {
            this.hide_empty_placeholder();
            var row_id = this.row_index++;
            this.rows[row_id] = new PCrudFilterRow(this, row_id);
        };

        this.remove_row = function(row_id) {
            this.rows[row_id].destroy();
            delete this.rows[row_id];

            if (openils.Util.objectProperties(this.rows).length < 1)
                this.show_empty_placeholder();
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

        this._init.apply(this, arguments);
    }

    /* As the name implies, objects of this class manage a single row of the
     * query.  Therefore they know about their own field dropdown, their own
     * selector dropdown, and their own value widget (or widgets in the case
     * of between searches, which call for two widgets to define a range),
     * and not much else. */
    function PCrudFilterRow() {
        var self = this;

        this._init = function(filter_row_manager, row_id) {
            this.filter_row_manager = filter_row_manager;
            this.row_id = row_id;

            this._build();
        };

        this._build = function() {
            this.tr = dojo.create("tr", {}, this.filter_row_manager.table);

            this._create_field_selector();
            this._create_operator_selector();
            this._create_value_slot();
            this._create_remover();
        };

        this._create_field_selector = function() {
            var td = dojo.create("td", {}, this.tr);
            this.field_selector = new dijit.form.FilteringSelect(
                {
                    "labelAttr": "label",
                    "searchAttr": "label",
                    "scrollOnFocus": false,
                    "onChange": function(value) {
                        self.update_selected_field(value);
                    },
                    "store": this.filter_row_manager.field_store
                }, dojo.create("span", {}, td)
            );
        };

        this._create_operator_selector = function() {
            var td = dojo.create("td", {}, this.tr);
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

        this._create_value_slot = function() {
            this.value_slot = dojo.create("td", {"innerHTML": "-"}, this.tr);
        };

        this._create_remover = function() {
            var td = dojo.create("td", {}, this.tr);
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
            if (this.value_widgets) {
                this.value_widgets.forEach(
                    function(autowidg) { autowidg.widget.destroy(); }
                );
                delete this.value_widgets;
            }

            dojo.empty(this.value_slot);
        };

        this._rebuild_value_widgets = function() {
            this._clear_value_slot();

            if (!this.get_selected_operator() || !this.selected_field)
                return;

            this.value_widgets = [];

            var param_count = this.operator_selector.item.param_count;

            for (var i = 0; i < param_count; i++) {
                var widg = new openils.widget.AutoFieldWidget({
                    "fmClass": this.selected_field_fm_class,
                    "fmField": this.selected_field_fm_field,
                    "parentNode": dojo.create("span", {}, this.value_slot),
                    "dijitArgs": {"scrollOnFocus": false}
                });

                widg.build();
                this.value_widgets.push(widg);
            }
        };

        /* for ugly special cases in compliation */
        this._null_clause = function() {
            var opname = this.get_selected_operator_name();
            if (opname == "not null")
                return {"!=": null};
            else if (opname == "null")
                return null;
            else
                return;
        };

        this.get_selected_operator = function() {
            if (this.operator_selector)
                return this.operator_selector.item;
        };

        this.get_selected_operator_name = function() {
            var op = this.get_selected_operator();
            return op ? op.name : null;
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
                //console.log(dojo.toJson(this.field_selector.item));
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

        this.compile = function() {
            if (this.value_widgets) {
                var values = this.value_widgets.map(
                    function(widg) {
                        return self.selected_field_is_indirect ?
                            widg.widget.attr('displayedValue') :
                            widg.getFormattedValue();
                    }
                );

                if (!values.length) {
                    return this._null_clause(); /* null/not null */
                } else {
                    var clause = {};
                    var op = this.get_selected_operator_name();
                    if (values.length == 1)
                        clause[op] = values.pop();
                    else
                        clause[op] = values;
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

        this._init.apply(this, arguments);
    }

    dojo.declare(
        'openils.widget.PCrudFilterDialog',
        [dijit.Dialog, openils.widget.AutoWidget],
        {

            constructor : function(args) {
                for(var k in args)
                    this[k] = args[k];
                this.title = this.title || pcFilterLocaleStrings.DEFAULT_DIALOG_TITLE;
                this.widgetIndex = 0;
                this.widgetCache = {};
            },

            _buildButtons : function() {
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

                new dijit.form.Button(
                    {
                        "label": pcFilterLocaleStrings.APPLY,
                        "scrollOnFocus": false,
                        "onClick": function() {
                            if (self.onApply)
                                self.onApply(self.filter_row_manager.compile());
                            self.hide();
                        }
                    }, dojo.create("span", {}, button_holder)
                );

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
            },

            _buildFieldStore : function() {
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

            /* All we really do here is create a data store out of the fields
             * from the IDL for our given class, place a few buttons at the
             * bottom of the dialog, and hand off to PCrudFilterRowManager to
             * do the actual work.
             */

            startup : function() {
                var self = this;
                this.inherited(arguments);
                this.initAutoEnv();

                this._buildFieldStore();

                this.filter_row_manager = new PCrudFilterRowManager(
                    dojo.create("div", {}, this.domNode),
                    this.fieldStore, this.fmClass
                );

                this._buildButtons();
            }
        }
    );
}

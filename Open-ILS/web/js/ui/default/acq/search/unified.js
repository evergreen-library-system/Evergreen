dojo.require("dojo.date.stamp");
dojo.require("dojox.encoding.base64");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.AutoWidget");
dojo.require("openils.widget.XULTermLoader");
dojo.require("openils.PermaCrud");

if (!localeStrings) {   /* we can do this because javascript doesn't have block 
                           scope */
    dojo.requireLocalization('openils.acq', 'acq');
    var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');
}

var termSelectorFactory;
var termManager;
var resultManager;
var uriManager;
var pcrud = new openils.PermaCrud();
var cgi = new openils.CGI();

/* typing save: add {get,set}Value() to all HTML <select> elements */
HTMLSelectElement.prototype.getValue = function() {
    return this.options[this.selectedIndex].value;
}

/* only sets the selected value if such an option is actually available */
HTMLSelectElement.prototype.setValue = function(s) {
    for (var i = 0; i < this.options.length; i++) {
        if (s == this.options[i].value) {
            this.selectedIndex = i;
            break;
        }
    }
}

/* minor formatting function used by autogrids in unified.tt2 */
function getName(rowIndex, item) {
    if (item) {
        return {
            "name": this.grid.store.getValue(item, "name") ||
                localeStrings.UNNAMED,
            "id": this.grid.store.getValue(item, "id")
        };
    }
}

/* quickly find elements by the value of a "name" attribute */
function nodeByName(name, root) {
    return dojo.query("[name='" + name + "']", root)[0];
}

function hideForm() {
    openils.Util.hide("acq-unified-hide-form");
    openils.Util.show("acq-unified-reveal-form", "inline");
    openils.Util.hide("acq-unified-form");
}

function revealForm() {
    openils.Util.hide("acq-unified-reveal-form");
    openils.Util.show("acq-unified-hide-form", "inline");
    openils.Util.show("acq-unified-form");
}

/* The TermSelectorFactory will be instantiated by the TermManager. It
 * provides HTML select controls whose options are all the searchable
 * fields.  Selecting a field from one of these controls will create the
 * appopriate type of corresponding widget for the user to enter a search
 * term against the selected field.
 */
function TermSelectorFactory(terms) {
    var self = this;
    this.terms = terms;
    this.onlyBibFriendly = false;

    this.template = dojo.create("select");
    this.template.appendChild(
        dojo.create("option", {
            "disabled": "disabled",
            "selected": "selected",
            "value": "",
            "innerHTML": localeStrings.SELECT_SEARCH_FIELD
        })
    );

    /* Create abbreviations for class names to make field categories
     * more readable in field selector control. */
    this._abbreviate = function(s) {
        var last, result;
        for (var i = 0; i < s.length; i++) {
            if (s[i] != " ") {
                if (!i) result = s[i];
                else if (last == " ") result += s[i];
            }
            last = s[i];
        }
        return result;
    };

    var selectorMethods = {
        /* Important: within the following functions, "this" refers to one
         * HTMLSelect object, and "self" refers to the TermSelectorFactory. */
        "getTerm": function() { return this.valueToTerm(this.getValue()); },
        "valueToTerm": function(value) {
            var parts = value.split(":");
            if (!parts || parts.length != 2) return null;
            return dojo.mixin(
                self.terms[parts[0]][parts[1]],
                {"hint": parts[0], "field": parts[1]}
            );
        },
        "onlyBibFriendly": function(yes) {
            if (yes) {
                for (var i = 0; i < this.options.length; i++) {
                    if (this.options[i].value) {
                        var term = this.valueToTerm(this.options[i].value);
                        this.options[i].disabled = !term.bib_friendly;
                    }
                }
            } else {
                for (var i = 0; i < this.options.length; i++) {
                    if (this.options[i].value)
                        this.options[i].disabled = false;
                }
            }
        },
        "makeWidget": function(
            parentNode, wStore, matchHow, value, noFocus, callback
        ) {
            var term = this.getTerm();
            var widgetKey = this.uniq;
            var target = termManager.getLinkTarget(term);

            if (matchHow.getValue() == "__in") {
                new openils.widget.XULTermLoader({
                    "parentNode": parentNode
                }).build(
                    function(w) {
                        wStore[widgetKey] = w;
                        if (typeof(callback) == "function")
                            callback(term, widgetKey);
                        if (typeof(value) != "undefined")
                            w.attr("value", value);
                        /* I would love for the following call not to be
                         * necessary, so that updating the value of the dijit
                         * would lead to this automatically, but I can't yet
                         * figure out the correct way to do this in Dojo.
                         */
                        w.updateCount();
                    }
                );
            } else if (term.hint == "acqlia" ||
                (term.hint == "jub" && term.field == "eg_bib_id") ||
                term.datatype == "org_unit" ||
                (term.datatype == "link" && target == "au")) {
                /* The test for jub.eg_bib_id is a special case to prevent
                 * AutoFieldWidget from trying to render a ridiculous dropdown
                 * of every bib record ID in the system. */
                wStore[widgetKey] = dojo.create(
                    "input", {"type": "text"}, parentNode, "only"
                );
                if (typeof(value) != "undefined")
                    wStore[widgetKey].value = value;
                if (!noFocus)
                    wStore[widgetKey].focus();
                if (typeof(callback) == "function")
                    callback(term, widgetKey);
            } else {
                new openils.widget.AutoFieldWidget({
                    "fmClass": term.hint,
                    "fmField": term.field,
                    "noDisablePkey": true,
                    "parentNode": dojo.create("span", null, parentNode, "only")
                }).build(
                    function(w) {
                        wStore[widgetKey] = w;
                        if (typeof(value) != "undefined") {
                            if (w.declaredClass.match(/Check/))
                                w.attr("checked", value == "t");
                            else
                                w.attr("value", value);
                        }
                        if (!noFocus)
                            w.focus();
                        if (typeof(callback) == "function")
                            callback(term, widgetKey);

                        // submit on enter
                        openils.Util.registerEnterHandler(w.domNode,
                            function() { 
                                resultManager.go(termManager.buildSearchObject());
                            }
                        );
                    }
                );
            }
        }
    }

    for (var hint in this.terms) {
        var optgroup = dojo.create(
            "optgroup", {"value": "", "label": this.terms[hint].__label}
        );
        var prefix = this._abbreviate(this.terms[hint].__label);

        for (var field in this.terms[hint]) {
            if (!/^__/.test(field)) {
                optgroup.appendChild(
                    dojo.create("option", {
                        "class": "acq-unified-option-regular",
                        "value": hint + ":" + field,
                        "innerHTML": prefix + " - " +
                            this.terms[hint][field].label
                    })
                );
            }
        }

        this.template.appendChild(optgroup);
    }

    this.make = function(n) {
        var node = dojo.clone(this.template);
        node.uniq = n;
        dojo.attr(node, "id", "term-" + n);
        for (var name in selectorMethods)
            node[name] = selectorMethods[name];
        if (this.onlyBibFriendly)
            node.onlyBibFriendly(true);
        return node;
    };
}

/* The term manager retrieves information from the IDL about all the fields
 * in the classes that we consider searchable for our purpose.  It maintains
 * a dynamic HTML table of search terms, using the TermSelectorFactory
 * to generate search field selectors, which in turn provide appropriate
 * widgets for entering search terms.  The TermManager provides search term
 * modifiers (fuzzy searching, not searching). The TermManager also handles
 * adding and removing rows of search terms, as well as building the search
 * query to pass to the middle layer from the search term widgets.
 */
function TermManager() {
    var self = this;

    /* All the keys in this object are bib-search-friendly attributes, but the
     * boolean values indicate whether they should be searched by their
     * field name as such, or simply mapped to "keyword". */
    this.bibFriendlyAttrNames = {
        "author": true, "title": true,
        "isbn": false, "issn": false, "upc": false
    };

    this.terms = {};
    ["jub", "acqpl", "acqpo", "acqinv"].forEach(
        function(hint) {
            var o = {};
            o.__label = fieldmapper.IDL.fmclasses[hint].label;
            fieldmapper.IDL.fmclasses[hint].fields.forEach(
                function(field) {
                    if (!field.virtual) {
                        o[field.name] = {
                            "label": field.label, "datatype": field.datatype
                        };
                    }
                }
            );
            self.terms[hint] = o;
        }
    );

    this.terms.acqlia = {"__label": fieldmapper.IDL.fmclasses.acqlia.label};
    pcrud.retrieveAll("acqliad", {"order_by": {"acqliad": "id"}}).forEach(
        function(def) {
            self.terms.acqlia[def.id()] = {
                "label": def.description(),
                "datatype": "text",
                "bib_friendly":
                    (typeof(self.bibFriendlyAttrNames[def.code()]) !=
                        "undefined"),
                "bib_attr_name":
                    self.bibFriendlyAttrNames[def.code()] ?
                        def.code() : "keyword"
            };
        }
    );

    this.selectorFactory = new TermSelectorFactory(this.terms);
    this.template = dojo.byId("acq-unified-terms-tbody").
        removeChild(dojo.byId("acq-unified-terms-row-tmpl"));
    dojo.attr(this.template, "id");

    this.lastResultType = null;

    this.rowId = 0;
    this.widgets = {};

    dojo.byId("acq-unified-result-type").onchange = function() {
        self.resultTypeChange(this.getValue());
    };

    this.allRowIds = function() {
        return dojo.query("tr[id^='term-row-']", "acq-unified-terms-tbody").
            map(function(o) { return o.id.match(/^term-row-(\d+)$/)[1]; });
    };

    this._row = function(id) { return dojo.byId("term-row-" + id); };
    this._selector = function(id) { return dojo.byId("term-" + id); };
    this._match_how = function(id) { return dojo.byId("term-match-" + id); };

    this._updateMatchHowForField = function(term, key) {
        /* NOTE important to use self, not this, in this function.
         *
         * Based on the selected field (its datatype and the kind of widget
         * that AutoFieldWidget provides for it) we update the possible
         * choices in the mach_how selector.
         */
        var w = self.widgets[key];
        var can_do_fuzzy, can_do_in;
        if (term.datatype == "id") {
            can_do_fuzzy = false;
            can_do_in = true;
        } else if (term.datatype == "link") {
            var target = self.getLinkTarget(term);
            can_do_fuzzy = (target == "au");
            can_do_in = (target == "bre"); /* XXX might revise later */
        } else if (typeof(w.declaredClass) != "undefined") {
            can_do_fuzzy = can_do_in =
                Boolean(w.declaredClass.match(/form\.Text|XULT/));
        } else {
            var type = dojo.attr(w, "type");
            if (type)
                can_do_fuzzy = can_do_in = (type == "text");
            else
                can_do_fuzzy = can_do_in = false;
        }

        self.matchHowAllow(key, "__fuzzy", can_do_fuzzy);
        self.matchHowAllow(key, "__in", can_do_in);

        var inequalities = (term.datatype == "timestamp");
        self.matchHowAllow(key, "__gte", inequalities);
        self.matchHowAllow(key, "__lte", inequalities);
    };

    this.removerButton = function(n) {
        return dojo.create("button", {
            "innerHTML": "X",
            "class": "acq-unified-remover",
            "onclick": function() { self.removeRow(n); }
        });
    };

    this.matchHowAllow = function(where, what, which, exact) {
        dojo.query(
            "option[value" + (exact ? "" : "*") + "='" + what + "']",
            typeof(where) == "object" ? where : this._match_how(where)
        ).forEach(function(o) { o.disabled = !which; });
    };

    this.getLinkTarget = function(term) {
        return fieldmapper.IDL.fmclasses[term.hint].
            field_map[term.field]["class"];
    };

    this.updateRowWidget = function(id, value, noFocus) {
        var where = nodeByName("widget", this._row(id));

        delete this.widgets[id];
        dojo.empty(where);

        this._selector(id).makeWidget(
            where, this.widgets, this._match_how(id), value, noFocus,
            this._updateMatchHowForField
        );
    };

    this.resultTypeChange = function(resultType) {
        if (
            this.lastResultType == "lineitem_and_bib" &&
            resultType != "lineitem_and_bib"
        ) {
            /* Re-enable all non-bib-friendly fields in all search term
             * field selectors. */
            this.allRowIds().forEach(
                function(id) {
                    self._selector(id).onlyBibFriendly(false);
                    self.matchHowAllow(id, "", true, /* exact */ true);
                    self.matchHowAllow(id, "__not", true, /* exact */ true);
                }
            );
            /* Tell the selector factory to create new search term field
             * selectors with all fields, not just bib-friendly ones. */
            this.selectorFactory.onlyBibFriendly = false;
        } else if (
            this.lastResultType != "lineitem_and_bib" &&
            resultType == "lineitem_and_bib"
        ) {
            /* Remove all search term rows set to non-bib-friendly fields. */
            this.allRowIds().forEach(
                function(id) {
                    var term = self._selector(id).getTerm();
                    if (term &&
                        !self.terms[term.hint][term.field].bib_friendly) {
                        self.removeRow(id);
                    }
                }
            );
            /* Disable all non-bib-friendly fields in all remaining search term
             * field selectors. */
            this.allRowIds().forEach(
                function(id) {
                    self._selector(id).onlyBibFriendly(true);
                    self.matchHowAllow(id, "", false, /* exact */ true);
                    self.matchHowAllow(id, "__not", false, /* exact */ true);
                }
            );
            /* Tell the selector factory to create new search term field
             * selectors with only bib friendly options. */
            this.selectorFactory.onlyBibFriendly = true;
        }
        this.lastResultType = resultType;
    };

    /* this method is particularly kludgy... puts back together a string
     * based on object properties that might arrive in indeterminate order. */
    this._term_reverse_match_how = function(term) {
        /* only two-key combination we use */
        if (term.__not && term.__fuzzy)
            return "__not,__fuzzy";

        /* only other possibilities are single-key or no key */
        for (var key in term) {
            if (/^__/.test(key))
                return key;
        }

        return null;
    };


    this._term_reverse_selector_field = function(term) {
        for (var key in term) {
            if (!/^__/.test(key))
                return key;
        }
        return null;
    };

    this._term_reverse_selector_value = function(term) {
        for (var key in term) {
            if (!/^__/.test(key))
                return term[key];
        }
        return null;
    };

    this.addRow = function(term, hint) {
        var uniq = (this.rowId)++;

        var row = dojo.clone(this.template);
        dojo.attr(row, "id", "term-row-" + uniq);

        var selector = this.selectorFactory.make(uniq);
        dojo.attr(
            selector, "onchange", function() { self.updateRowWidget(uniq); }
        );

        var match_how = dojo.query("select", nodeByName("match", row))[0];
        dojo.attr(match_how, "id", "term-match-" + uniq);
        dojo.attr(match_how, "selectedIndex", 0);
        dojo.attr(
            match_how, "onchange",
            function() {
                if (this.getValue() == "__in") {
                    self.updateRowWidget(uniq);
                    this.was_in = true;
                } else if (this.was_in) {
                    self.updateRowWidget(uniq);
                    this.was_in = false;
                }
                if (self.widgets[uniq]) self.widgets[uniq].focus();
            }
        );

        /* Kind of inelegant; could be improved: this section turns off
         * match-type options that don't apply to bib searching. */
        this.matchHowAllow(
            match_how, "",
            !this.selectorFactory.onlyBibFriendly, /* exact */ true
        );
        this.matchHowAllow(
            match_how, "__not",
            !this.selectorFactory.onlyBibFriendly, /* exact */ true
        );
        if (this.selectorFactory.onlyBibFriendly)
            match_how.setValue("__fuzzy");

        nodeByName("selector", row).appendChild(selector);
        nodeByName("remove", row).appendChild(this.removerButton(uniq));

        dojo.place(row, "acq-unified-terms-tbody", "last");

        if (term && hint) {
            var attr = this._term_reverse_selector_field(term);
            var field = hint + ":" + attr;
            selector.setValue(field);

            var match_how_value = this._term_reverse_match_how(term);
            if (match_how_value)
                match_how.setValue(match_how_value);

            var value = this._term_reverse_selector_value(term);
            if (this.terms[hint][attr].datatype == "timestamp")
                value = dojo.date.stamp.fromISOString(value);
            this.updateRowWidget(uniq, value, /* noFocus */ true);

        }
    }

    this.removeRow = function(id) {
        delete this.widgets[id];
        dojo.destroy(this._row(id));
    };

    this.reflect = function(search_object) {
        for (var hint in search_object) {
            search_object[hint].forEach(
                function(term) { self.addRow(term, hint); }
            );
        }
    };

    this.buildSearchObject = function() {
        var so = {};

        for (var id in this.widgets) {
            var kvlist = this._selector(id).getValue().split(":");
            var hint = kvlist[0];
            var attr = kvlist[1];
            if (!(hint && attr)) continue;

            var match_how =
                this._match_how(id).getValue().split(",").filter(Boolean);

            var value;
            if (typeof(this.widgets[id].declaredClass) != "undefined") {
                if (this.widgets[id].declaredClass.match(/Date/)) {
                    value =
                        dojo.date.stamp.toISOString(this.widgets[id].value).
                            split("T")[0];
                } else {
                    value = this.widgets[id].attr("value");
                    if (this.widgets[id].declaredClass.match(/Check/))
                        value = (value == "on") ? "t" : "f";
                }
            } else {
                value = this.widgets[id].value;
            }

            if (!so[hint])
                so[hint] = [];

            var unit = {};
            unit[attr] = value;
            match_how.forEach(function(key) { unit[key] = true; });
            if (this.terms[hint][attr].datatype == "timestamp")
                unit.__castdate = true;

            so[hint].push(unit);
        }
        return so;
    };

    this.buildBibSearchString = function() {
        var conj = {"and": " ", "or": " || "}[
            dojo.byId("acq-unified-conjunction").getValue()
        ];

        var sso = {};
        /* Notice that below we use conj in two places and a constant " || "
         * in one. That constant " || " is applied for the "file of terms"
         * search term type, which is in itself always an or search. */
        for (var id in this.widgets) {
            var term = this._selector(id).getTerm();
            var attr = term.bib_attr_name;
            var match_how = this._match_how(id).getValue();
            var widget = this.widgets[id];

            if (!sso[attr]) sso[attr] = [];
            var  value = (
                typeof(widget.attr) == "function" ?
                    widget.attr("value") : widget.value
            );
            if (typeof(value) != "string")
                value = value.join(" || ");
            sso[attr].push(
                (match_how.indexOf("__not") == -1 ? "" : "-") + value
            );
        }
        var ssa = [];
        for (var attr in sso)
            ssa.push(attr + ": " + sso[attr].join(conj));
        return "(" + ssa.join(conj) + ")";
    };
}

/* The result manager is used primarily when the users submits a search.  It
 * consults the termManager to get the search query to send to the middl
 * layer, and it chooses which ML method to call as well as what widgets to use
 * to display the results.
 */
function ResultManager(liPager, poGrid, plGrid, invGrid) {
    var self = this;

    this.liPager = liPager;

    this.poGrid = poGrid;
    this.plGrid = plGrid;
    this.invGrid = invGrid;
    this.poCache = {};
    this.plCache = {};
    this.invCache = {};

    this.result_types = {
        "lineitem": {
            "search_options": {
                "flesh_attrs": true,
                "flesh_cancel_reason": true,
                "flesh_notes": true
            },
            "revealer": function() {
                self.liPager.show();
                progressDialog.show(true);
            },
            "finisher": function() {
                self.liPager.batch_length = self.count_results;
                self.liPager.relabelControls();
                self.liPager.enableControls(true);
                progressDialog.hide();
            },
            "adder": function(li) {
                self.liPager.liTable.addLineitem(li);
            },
            "interface": self.liPager
        },
        "purchase_order": {
            "search_options": {
                "no_flesh_cancel_reason": true
            },
            "revealer": function() {
                self.poGrid.resetStore();
                self.poGrid.showLoadProgressIndicator();
                self.poCache = {};
            },
            "finisher": function() {
                self.poGrid.hideLoadProgressIndicator();
            },
            "adder": function(po) {
                self.poCache[po.id()] = po;
                self.poGrid.store.newItem(acqpo.toStoreItem(po));
            },
            "interface": self.poGrid
        },
        "picklist": {
            "search_options": {
                "flesh_lineitem_count": true,
                "flesh_owner": true
            },
            "revealer": function() {
                self.plGrid.resetStore();
                self.plGrid.showLoadProgressIndicator();
                self.plCache = {};
            },
            "finisher": function() {
                self.plGrid.hideLoadProgressIndicator();
            },
            "adder": function(pl) {
                self.plCache[pl.id()] = pl;
                self.plGrid.store.newItem(acqpl.toStoreItem(pl));
            },
            "interface": self.plGrid
        },
        "invoice": {
            "search_options": {
                "no_flesh_misc": true
            },
            "finisher": function() {
                self.invGrid.hideLoadProgressIndicator();
            },
            "revealer": function() {
                self.invGrid.resetStore();
                self.invCache = {};
            },
            "adder": function(inv) {
                self.invCache[inv.id()] = inv;
                self.invGrid.store.newItem(acqinv.toStoreItem(inv));
            },
            "interface": self.invGrid
        },
        "no_results": {
            "revealer": function() { alert(localeStrings.NO_RESULTS); }
        }
    };

    this._dataLoader = function(opts) {
        /* This function must contain references to "self" only, not "this." */
        var grid = self.result_types[self.result_type].interface;

        if (!opts)
            opts = {};

        self.count_results = 0;

        var use_params = dojo.clone(self.params);   /* need copy, not ref */

        if (!opts.skip_paging) {
            use_params[4].offset = grid.displayOffset;
            use_params[4].limit = grid.displayLimit;
        }

        var method = self.method_name;
        if (opts.atomic)
            method += ".atomic";

        if (opts.id_list)
            use_params[4].id_list = true;

        var request_options = {
            "params": use_params,
            "async": true
        };

        if (typeof opts.onresponse != "undefined") {
            request_options.onresponse = opts.onresponse;
        } else {
            /* normal onresponse handler for most times we call this method */
            request_options.onresponse = function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (!self.count_results++)
                        self.show(self.result_type);
                    self.add(self.result_type, r);
                }
            };
        }

        if (typeof opts.oncomplete != "undefined") {
            request_options.oncomplete = opts.oncomplete;
        } else {
            /* normal oncomplete handler for most times we call this method */
            request_options.oncomplete = function() { self.resultsComplete(); };
        }

        fieldmapper.standardRequest(["open-ils.acq", method], request_options);
    };

    this.add = function(which, what) {
        var f = this.result_types[which].adder;
        if (f) f(what);
    };

    this.finish = function(which) {
        var f = this.result_types[which].finisher;
        if (f) f();
    };

    this.show = function(which) {
        openils.Util.objectProperties(this.result_types).forEach(
            function(rt) {
                openils.Util[rt == which ? "show" : "hide"](
                    "acq-unified-results-" + rt
                );
            }
        );
        this.result_types[which].revealer();
    };

    this.resultsComplete = function() {

        // now that the records are loaded, we need to do the actual focusing
        if (this.result_type == 'lineitem') {
            if (this.liPager) 
                this.liPager.focusLi();
        }

        if (!this.count_results)
            this.show("no_results");
        else this.finish(this.result_type);
    };

    this.go = function(search_object) {
        location.href = oilsBasePath + "/acq/search/unified?" +
            "so=" + base64Encode(search_object) +
            "&rt=" + dojo.byId("acq-unified-result-type").getValue() +
            "&c=" + dojo.byId("acq-unified-conjunction").getValue();
    };

    this.search = function(uriManager, termManager) {
        var bib_search_string = null;
        this.count_results = 0;
        this.result_type = dojo.byId("acq-unified-result-type").getValue();

        /* lineitem_and_bib: a special case */
        if (this.result_type == "lineitem_and_bib") {
            this.result_type = "lineitem";
            bib_search_string = termManager.buildBibSearchString();
        }

        this.method_name = "open-ils.acq." + this.result_type +
            ".unified_search";
        /* Except for building the API method name that we want to call,
         * we want to treat lineitem_and_bib the same way as lineitem from
         * here forward. */

        this.params = [
            openils.User.authtoken,
            null, null, null,
            this.result_types[this.result_type].search_options
        ];

        this.params[
            dojo.byId("acq-unified-conjunction").getValue() == "and" ? 1 : 2
        ] = uriManager.search_object;
        if (uriManager.order_by)
            this.params[4].order_by = uriManager.order_by;

        var interface = this.result_types[this.result_type].interface;
        interface.dataLoader = this._dataLoader;

        if (bib_search_string) {
            /* Have the ML do the bib search first, which incidentally has the
             * side effect of creating line items that will show up when
             * we do the LI part of the search (so we don't actually want
             * to display these results directly). */
            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.biblio.wrapped_search.atomic"], {
                    "params": [
                        openils.User.authtoken, bib_search_string, {
                            "clear_marc": true
                        }
                    ],
                    "onresponse": function(r) {
                        r = openils.Util.readResponse(r, false, true);
                    }
                }
            );
        }

        // if the caller has requested we focus on a specific
        // lineitem, allow the pager to find the lineitem
        // and load the results directly.
        if (this.result_type == 'lineitem') {
            if (this.liPager && this.liPager.loadFocusLi()) { 
                return;
            }
        }

        interface.dataLoader();
    };
}

function URIManager() {
    var self = this;
    this.cannedSearches = {
        "po": {
            "search_object": {
                "acqpo": [
                    {"ordering_agency": openils.User.user.ws_ou()},
                    {"state": "on-order"}
                ]
            },
            "half_search": true,
            "result_type": "purchase_order",
            "conjunction": "and",
            "order_by": [
                {"class": "acqpo", "field": "edit_time", "direction": "desc"}
            ]
        },
        "pl": {
            "search_object": {
                "acqpl": [
                    {"owner": openils.User.user.usrname()}
                ]
            },
            "result_type": "picklist",
            "conjunction": "and",
            "order_by": [
                {"class": "acqpl", "field": "edit_time", "direction": "desc"}
            ]
        },
        "inv": {
            "search_object": {
                "acqinv": [
                    {"complete": "f"},
                    {"receiver": openils.User.user.ws_ou()}
                ]
            },
            "half_search": true,
            "result_type": "invoice",
            "conjunction": "and",
            "order_by": [
                {"class": "acqinv", "field": "recv_date", "direction": "desc"}
            ]
        }
    };

    if (this.canned = cgi.param("ca")) { /* assignment */
        dojo.mixin(this, this.cannedSearches[this.canned]);
        dojo.byId("acq-unified-result-type").setValue(this.result_type);
        dojo.byId("acq-unified-result-type").onchange();
        dojo.byId("acq-unified-conjunction").setValue(this.conjunction);
    } else {
        this.search_object = cgi.param("so");
        if (this.search_object)
            this.search_object = base64Decode(this.search_object);

        this.result_type = cgi.param("rt");
        if (this.result_type) {
            dojo.byId("acq-unified-result-type").setValue(this.result_type);
            dojo.byId("acq-unified-result-type").onchange();
        }

        this.conjunction = cgi.param("c");
        if (this.conjunction)
            dojo.byId("acq-unified-conjunction").setValue(this.conjunction);
    }
}

/* onload */
openils.Util.addOnLoad(
    function() {
        termManager = new TermManager();
        resultManager = new ResultManager(
            new LiTablePager(null, new AcqLiTable()),
            dijit.byId("acq-unified-po-grid"),
            dijit.byId("acq-unified-pl-grid"),
            dijit.byId("acq-unified-inv-grid")
        );

        uriManager = new URIManager();
        if (uriManager.search_object) {
            if (!uriManager.half_search)
                hideForm();
            openils.Util.show("acq-unified-body");
            termManager.reflect(uriManager.search_object);

            if (!uriManager.half_search)
                resultManager.search(uriManager, termManager);
        } else {
            termManager.addRow();
            openils.Util.show("acq-unified-body");
        }
    }
);

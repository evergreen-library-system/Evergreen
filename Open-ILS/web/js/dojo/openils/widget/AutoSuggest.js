if (!dojo._hasResource["openils.widget.AutoSuggest"]) {
    dojo.provide("openils.widget.AutoSuggest");
    dojo._hasResource["openils.widget.AutoSuggest"] = true;

    dojo.require("dijit.form.ComboBox");
    dojo.require("openils.AutoSuggestStore");

    /* Do some monkey-patching on dijit.form._ComboBoxMenu to make AutoSuggest
     * widget behavior more Google-like, and do it within a function to prevent
     * namespace pollution. */

    (function() {
        var victim = dijit.form._ComboBoxMenu;

        /* Assist in making clicking on a suggestion lead directly to search.
         * Relies on overridden _startSearch() in the widget below. */
        var _orig_onMouseUp = victim.prototype._onMouseUp;
        victim.prototype._onMouseUp = function(evt) {
            if (this.parent_widget)
                this.parent_widget.mouse_used_most_recently = true;
            dojo.hitch(this, _orig_onMouseUp)(evt);
        };

        /* These next two, taken together, prevent the user from having to
         * type space twice after selecting (with arrow keys) an item from
         * the autosuggestions. */
        var _orig_handleKey = victim.prototype.handleKey;
        victim.prototype.handleKey = function(key) {
            /* Testing for this.parent_widget's existence allows our patch
             * not to be intrusive if /other/ widgets (besides
             * openils.widget.AutoSuggest) are using d.f._ComboBoxMenu on the
             * same page. */
            if (this.parent_widget && key == " ") {
                this.just_had_space = true;
            } else {
                this.just_had_space = false;
                return dojo.hitch(this, _orig_handleKey)(key);
            }
        }

        var _orig_getHighlightedOption = victim.prototype.getHighlightedOption;
        victim.prototype.getHighlightedOption = function() {
            if (this.just_had_space) {
                this.just_had_space = false;
                return null;
            } else {
                return dojo.hitch(this, _orig_getHighlightedOption)();
            }
        }
    })();

    dojo.declare(
        "openils.widget.AutoSuggest", [dijit.form.ComboBox], {

            "scrollOnFocus": false,
            "labelAttr": "match",
            "labelType": "html",
            "searchAttr": "term",
            "hasDownArrow": false,
            "autoComplete": false,
            "searchDelay": 200,

            /* Don't forget to these two parameters when instantiating. */
            "submitter": function() { console.log("No submitter connected"); },
            "type_selector": null,  /* see openils.AutoSuggestStore for docs */

            "store_args": {},

            "mouse_used_most_recently": false,

            "_update_search_type_selector": function(id) {  /* cmf id */
                if (!this.store.cm_cache.is_done) {
                    console.warn(
                        "can't update search type selector; " +
                        "store doesn't have config.metabib_* caches available"
                    );
                    return;
                }

                var f = this.store.cm_cache.cmf[id];
                var selector = this.type_selector;
                var search_class = f.field_class + "|" + f.name;
                var exact = dojo.indexOf(
                    dojo.map(selector.options, function(o) { return o.value; }),
                    search_class
                );

                if (exact > 0) {
                    selector.selectedIndex = exact;
                } else {    /* settle for class match if we can get it */
                    for (var i = 0; i < selector.options.length; i++) {
                        if (selector.options[i].value.split("|")[0] ==
                                f.field_class) {
                            selector.selectedIndex = i;
                            break;
                        }
                    }
                }
            },

            "_startSearch": function() {
                this.inherited(arguments);
                this._popupWidget.parent_widget = this;
            },

            "_setCaretPos": function(element, loc) {
                /* selects nothing, puts cursor at the end of the string */
                dijit.selectInputText(element, element.value.length);
            },

            "_autoCompleteText": function() {
                var orig = dijit.selectInputText;
                dijit.selectInputText = function() { };

                this.inherited(arguments);

                dijit.selectInputText = orig;
            },

            "onChange": function(value) {
                if (typeof value.field == "number") {
                    this._update_search_type_selector(value.field);

                    /* If onChange fires and the following condition is true,
                     * it must mean that the user clicked on an actual
                     * suggestion with the mouse.  We also perform our search
                     * when the user presses enter (handled elsewhere), but not
                     * when the user selects something and keeps typing. */
                    if (this.mouse_used_most_recently)
                        this.submitter();
                }
            },

            "postMixInProperties": function() {
                this.inherited(arguments);

                if (typeof this.submitter == "string")
                    this.submitter = dojo.hitch(this, this.submitter);

                if (typeof this.type_selector == "string")
                    this.type_selector = dojo.byId(this.type_selector);

                /* Save the instantiator from needing to specify same thing
                 * twice, even though we need it and the store needs it too. */
                if (this.type_selector && !this.store_args.type_selector)
                    this.store_args.type_selector = this.type_selector;

                this.store = new openils.AutoSuggestStore(this.store_args);
            },

            "postCreate": function() {
                this.inherited(arguments);

                dojo.connect(
                    this, "onKeyPress", this, function(evt) {
                        this.mouse_used_most_recently = false;
                        if (evt.keyCode == dojo.keys.ENTER)
                            this.submitter();
                    }
                );
            }
        }
    );
}

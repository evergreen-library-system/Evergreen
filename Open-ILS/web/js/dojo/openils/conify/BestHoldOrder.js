if (!dojo._hasResource["openils.conify.BestHoldOrder"]) {
    dojo.requireLocalization("openils.conify", "conify");

    dojo._hasResource["openils.conify.BestHoldOrder"] = true;
    dojo.provide("openils.conify.BestHoldOrder");
    dojo.provide("openils.conify.SetOrderer");

    dojo.require("dojo.string");
    dojo.require("openils.Util");
    dojo.require("openils.User");
    dojo.require("openils.PermaCrud");
    dojo.require("openils.widget.AutoFieldWidget");

(function() {
    var localeStrings =
        dojo.i18n.getLocalization("openils.conify", "conify");

    /* This helper module is OO. */
    dojo.declare(
        "openils.conify.SetOrderer", null, {
            "constructor": function(select, field_map, format_string) {
                this.select = select;   /* HTML <select> node */
                this.field_map = field_map; /* object of id:label pairs */
                this.format_string = format_string || "[${0}] ${1}";
            },

            "clear": function() {
                dojo.forEach(
                    this.select.options,
                    dojo.hitch(
                        this, function(o) { this.select.options.remove(o); }
                    )
                );
            },

            /* This trusts that what you are passing is actually a set (no
             * repeats). */
            "set": function(
                set, pos_callback /* called for each set member's <option>
                                     node now and at any position change */
            ) {
                this.clear();
                this.pos_callback = pos_callback;
                dojo.forEach(
                    set, dojo.hitch(this, function(o, p) { this.add(o, p); })
                );
            },

            "focus": function() {
                this.select.focus();
            },

            /* For now this trusts that your item is in the field_map */
            "add": function(item, position) {
                var option = dojo.create(
                    "option", {
                        "value": item,
                        "innerHTML": dojo.string.substitute(
                            this.format_string, [item, this.field_map[item]]
                        )
                    }
                );

                this.select.options.add(option, null);
                if (this.pos_callback)
                    this.pos_callback(option, position);
            },

            /* Returns option values in order, as a set, assuming you didn't
             * add dupes. */
            "get": function() {
                /* XXX Could probably use dojo.forEach() here, but don't have
                 * time to check whether it's sure to preserve order
                 * with pseudo-arrays or NodeLists or whatever this is. */
                var list = [];
                for (var i = 0; i < this.select.options.length; i++)
                    list.push(this.select.options[i].value);

                return list;
            },

            "move_selected": function(offset) {
                var si = this.select.selectedIndex;
                if (si < 0)
                    return false;

                var opt = this.select.options[si];
                var len = this.select.options.length;
                var newpos = si + offset;

                if (newpos >= 0 && newpos < len) {
                    var newopt = dojo.clone(opt);
                    this.select.remove(si);
                    this.select.add(newopt, newpos);

                    if (this.pos_callback)
                        for (var i = 0; i < len; i++)
                            this.pos_callback(this.select.options[i], i);

                    this.select.selectedIndex = newpos;
                    return true;
                } else {
                    return false;
                }
            },
        }
    );

    /* This module is *not* OO. */
    dojo.declare("openils.conify.BestHoldOrder", null, {});

    var module = openils.conify.BestHoldOrder;

    /* We could get these from the IDL, but if we add more fields to that
     * later, we have no particular mechanism for determining what is or
     * isn't metadata. */
    module.fields = ["pprox", "hprox", "owning_lib_to_home_lib_prox",
        "aprox", "priority", "cut", "depth", "htime", "rtime", "approx",
        "shtime"];

    module.init = function() {
        module.progress_dialog = dijit.byId("progress-dialog");
        module.existing_dialog = dijit.byId("cbho-existing");

        dojo.connect(
            dijit.byId("cbho-existing-edit-go"),
            "onClick",
            null,
            module.editor_load_selected_cbho
        );

        module.field_labels = {};
        dojo.forEach(
            module.fields, function(f) {
                module.field_labels[f] = fieldmapper.IDL.fmclasses.cbho.
                    field_map[f].label
            }
        );

        module.set_orderer = new openils.conify.SetOrderer(
            dojo.byId("cbho-field-order"),
            module.field_labels,
            localeStrings.CBHO_FIELD_DISPLAY
        );

        openils.Util.hide("cbho-loading");
        openils.Util.show("cbho-main-body");
    };

    module.new_cbho = function() {
        module.cbho = new fieldmapper.cbho();

        module.editor_start();
    };

    module.edit_cbho = function() {
        module.progress_dialog.show(true);

        function proceed(w) {
            module.edit_cbho_selector = w;
            module.progress_dialog.hide();
            module.existing_dialog.show();
        };

        if (module.edit_cbho_selector) {
            proceed(module.edit_cbho_selector);
        } else {
            new openils.widget.AutoFieldWidget({
                "fmClass": "cbho",
                "selfReference": true,
                "dijitArgs": {"required": true},
                "parentNode": dojo.create(
                    "span", null, dojo.byId("cbho-existing-selector")
                )
            }).build(proceed);
        }
    };

    /* Causes next use of Edit Existing button to recreate, thereby picking
     * up any new objects */
    module.clear_cbho_selector = function() {
        if (module.edit_cbho_selector) {
            module.edit_cbho_selector.destroy();
            module.edit_cbho_selector = null;
        }
    };

    module.editor_load_selected_cbho = function() {
        var id = module.edit_cbho_selector.attr("value");

        if (id) {
            module.cbho = (new openils.PermaCrud()).retrieve("cbho", id);
            module.editor_start();
        } else {
            alert(localeStrings.CBHO_NO_LOAD);
        }
    };

    module.editor_start = function() {
        dojo.byId("cbho-editing").innerHTML = module.cbho.id() ?
            dojo.string.substitute(
                localeStrings.CBHO_EDITING_EXISTING,
                [module.cbho.id(), module.cbho.name()]
            ) :
            localeStrings.CBHO_EDITING_NEW;

        dojo.byId("cbho-name").value = module.cbho.name() || "";
        module.editor_reset_order();

        openils.Util.show("cbho-edit-space");
        module.editor_changed(false);
    };

    /* Used to set all <option> nodes in the set_orderer to appear disabled if
     * they now come after rtime. */
    module.set_pos_callback = function(opt_node, pos) {
        var method = module.rtime_reached ? "addClass" : "removeClass";
        dojo[method](opt_node, "post-rtime");

        if (opt_node.value == "rtime")
            module.rtime_reached = true;
    };

    module.stored_cbho_field_order = function() {
        var obj = module.cbho;

        return module.fields.sort(
            function(a, b) {
                a = obj[a]();
                var left = (a === null || typeof a == "undefined") ?
                    999 : Number(a);

                b = obj[b]();
                var right = (b === null || typeof b == "undefined") ?
                    999 : Number(b);

                return left - right;
            }
        );
    };

    module.editor_reset_order = function() {
        module.rtime_reached = false;
        module.set_orderer.set(
            module.stored_cbho_field_order(), module.set_pos_callback
        );
    };

    module.editor_move = function(offset) {
        module.rtime_reached = false;
        if (module.set_orderer.move_selected(offset))
            module.editor_changed(true);

        /* Without this, focus is now on the up or down button, breaking
         * the user's ability to select other rows with the arrow keys. */
        module.set_orderer.focus();
    };

    module.editor_changed = function(changed) {
        dojo.attr("cbho-save-changes", "disabled", !changed);
        if (changed)
            openils.Util.show("cbho-needs-saved", "inline");
        else
            openils.Util.hide("cbho-needs-saved");
    };

    module.editor_save = function() {
        var name = dojo.byId("cbho-name").value;
        if (!name || !name.length) {
            alert(localeStrings.CBHO_NEEDS_NAME);
            return false;
        } else {
            module.cbho.name(name);
        }

        module.progress_dialog.show(true);
        var fields = module.set_orderer.get();
        for (var i = 0; i < fields.length; i++)
            module.cbho[fields[i]](i);

        try {
            var pcrud = new openils.PermaCrud();
            pcrud[module.cbho.id() ? "update" : "create"](
                module.cbho, {
                    "oncomplete": function(r, list) {
                        module.progress_dialog.hide();
                        openils.Util.readResponse(r); /* alert on exceptions? */

                        if (dojo.isArray(list) && list.length) {
                            if (typeof list[0] == "object")
                                module.cbho = list[0];

                            module.clear_cbho_selector();
                            module.editor_start();
                        }

                        pcrud.session.disconnect(); /* good hygiene? */
                    }
                }
            );
        } catch (E) {
            alert(E);   /* better than doing nothing? */
        }
    };

})();

}

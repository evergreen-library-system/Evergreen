if (!dojo._hasResource["openils.widget.PhysCharWizard"]) {
    dojo._hasResource["openils.widget.PhysCharWizard"] = true;

    dojo.provide("openils.widget.PhysCharWizard");
    dojo.require("dojo.string");
    dojo.require("openils.User");
    dojo.require("openils.Util");
    dojo.require("openils.PermaCrud");
    dojo.requireLocalization("openils.widget", "PhysCharWizard");

    (function() {   /* Namespace protection so we can still make little helpers
                    within our own bubble */

        var _xhtml_ns = "http://www.w3.org/1999/xhtml";

        function _show_button(n, yes) { /* yet another hide/reveal thing */
            /* This is a re-invented wheel, but I was having trouble
             * getting my <button>s to react to the disabled property, and
             * decided to hide/reveal them instead of disable/enable then.
             * Then I had this need to do it in a consistent way. */
            n.setAttribute("style", "visibility: " + (yes? "visible":"hidden"));
        }

        function _get_xul_combobox_value(menulist) {
            /* XUL comboboxes (<menulist editable="true">) are funny. */

            return menulist.selectedItem ?
                menulist.selectedItem.value :
                menulist.label;  /* sic! Even .getAttribute('label') is
                                    wrong, and anything to do with 'value'
                                    is also wrong. */
        }

        /* Within the openils.widget.PhysCharWizard class, methods and
         * properties that start "_" should be considered private, and others
         * public.
         *
         * The methods whose names end in "_XUL" could be replaced with HTML
         * versions to make this wizard work as an HTML thing instead of as
         * a XUL thing.
         */
        dojo.declare(
            "openils.widget.PhysCharWizard", [], {
                "active": true,
                "constructor": function(args) {
                    this._ = openils.widget.PhysCharWizard.localeStrings;
                    this._cache = openils.widget.PhysCharWizard.cache;

                    /* Reserve a little of the window namespace that we'll need
                     * (under XUL anyway) */
                    window._owPCWinstances = window._owPCWinstances || 0;
                    window._owPCW = window._owPCW || {};
                    this.instance_num = window._owPCWinstances++;
                    window._owPCW[this.instance_num] = this;
                    this.outside_ref =
                        "window._owPCW[" + this.instance_num + "]";

                    /* Initialize and save misc values, and call build() to
                     * make and place widgets. */
                    this.onapply = args.onapply;

                    this.step = 'a';
                    this.more_back = false;
                    this.more_forward = true;
                    this.value = this.original_value = args.node.value;

                    this.pcrud = new openils.PermaCrud(
                        {"authtoken": ses ? ses() : openils.User.authtoken}
                    );

                    this.build(args.node);

                    this._load_all_types(   /* and then: */
                        dojo.hitch(this, function() { this.move(0); })
                    );
                },
                "build": function(where) {
                    this.original_node = where;
                    var p = this.container_node = where.parentNode;
                    p.removeChild(where);

                    this._build_XUL();
                },
                "update_question": function(label, values) {
                    this._update_question_XUL(label, values);
                },
                "update_value_label": function() {
                    this._update_value_label_XUL(
                        this._get_step_slot(), this.value
                    );
                },
                "update_pagers": function() {
                    _show_button(this.back_button, this.more_back);
                    _show_button(this.forward_button, this.more_forward);
                },
                "apply": function(callback) {
                    this.active = false;

                    this.move(
                        0, dojo.hitch(this, function() {
                            this.onapply(this.value);
                            if (typeof callback == "function")
                                callback();
                        })
                    );
                },
                "cancel": function() {
                    this.active = false;
                    this.container_node.removeChild(this.wizard_root_node);
                    this.container_node.appendChild(this.original_node);
                },
                "_default_after_00": function() {
                    /* This method assumes that the things it looks for in
                     * the cache are freshly put there. */
                    var working_ptype = this.value.substr(0, 1);
                    var sf_list = this._cache.subfields[working_ptype];
                    if (!sf_list)
                        throw new Error(this._.BAD_WORKING_PTYPE);

                    this.value = working_ptype;
                    for (var i = 0; i < sf_list.length; i++) {
                        var s = sf_list[i];
                        var gap = s.start_pos() - this.value.length;
                        if (gap > 0) {
                            for (var j = 0; j < gap; j++)
                                this.value += " ";  /* XXX or '#' ? */
                        } else if (gap < 0) {
                            throw new Error(
                                dojo.string.substitute(
                                    this._.BACKWARDS_SUBFIELD_PROGRESSION,
                                    [working_ptype]
                                )
                            );
                        }

                        for (var j = 0; j < s.length(); j++)
                            this.value += "|";
                    }
                },
                "move": function(offset, callback) {
                    /* When we move the wizard, we need to accomplish five
                     * things:
                     *  1) Disable both pager buttons - sic
                     *  2) Update the appopriate _slot of the working _value_
                     *  with the value from the user input control.
                     *  ---- sync above here ^ --------- async below here v ----
                     *  3) Determine what the next _step_ will be and set it
                     *  4) Replace the question and the dropdown with appro-
                     *  priate data from the new _step_
                     *  5) Reenable appropriate pager buttons
                     *  6) (optional) fire any callback
                     */

                    /* Step 1 */
                    _show_button(this.back_button, false);
                    _show_button(this.forward_button, false);

                    /* Step 2. No sweat so far. Skip if there is no
                     * user control yet (initializing whole wizard still). */
                    var a_changed = false;
                    if (this.step_user_control) {
                        a_changed = this.update_value_slot(
                                this._get_step_slot(),
                                this.get_step_value_from_control()
                            ) && this.step == 'a';
                    }

                    /* Step 3 depends on knowing a) our working_ptype, which
                     * may have just changed if step was 'a' and b) all the
                     * subfields for that ptype, which we may have to
                     * retrieve asynchronously. */
                    this._get_subfields_for_type(
                        this.value.substr(0, 1), /* working_ptype */
                        /* and then: */ dojo.hitch(this, function() {

                            /* Step 2.9 (small) */
                            if (a_changed) this._default_after_00();

                            /* Step 3 proper: */
                            this._move_step(offset);

                            /* Step 4: For the call to update_question, we had
                             * better have values loaded for our current step.
                             */
                            this._get_values_for_step(
                                this.step,
                                /* and then: */ dojo.hitch(this, function(l, v){
                                    /* Step 4 proper: */
                                    this.update_value_label();
                                    this.update_question(l, v);

                                    /* Step 5 */
                                    this.update_pagers();

                                    if (typeof callback == "function") {
                                        callback();
                                    }
                                })
                            );
                        })
                    );
                },
                "get_step_value_from_control": function() {
                    return _get_xul_combobox_value(this.step_user_control);
                },
                "get_step_value": function() {
                    return String.prototype.substr.apply(
                        this.value, this._get_step_slot()
                    );
                },
                "update_value_slot": function(slot, value) {
                    /* Return true if this.value changes */

                    if (!value.length) {
                        /* Prevent erasing positions when backing up. */
                        for (var i = 0; i < slot[1]; i++)
                            value += '|';
                    }

                    var old_value = this.value;
                    var before = this.value.substr(0, slot[0]);
                    var after = this.value.substr(slot[0] + slot[1]);

                    this.value = before + value.substr(0, slot[1]) + after;
                    return (this.value != old_value);
                },
                "_load_all_types": function(callback) {
                    /* It's easiest to have these always ready, and it's not
                     * a large dataset. */

                    if (this._cache.types.length)  /* maybe we already do */
                        callback();

                    this.pcrud.retrieveAll(
                        "cmpctm", {
                            "oncomplete": dojo.hitch(this, function(r) {
                                if (r = openils.Util.readResponse(r)) {
                                    this._cache.types = r.map(
                                        function(o) {
                                            return [o.ptype_key(), o.label()];
                                        }
                                    );
                                    callback();
                                } else {
                                    throw new Error(this._.DATA_ERROR_007);
                                }
                            })
                        }
                    );
                },
                "_get_subfields_for_type": function(working_ptype, callback) {
                    if (this._cache.subfields[working_ptype]) {
                        callback(this._cache.subfields[working_ptype]);
                    } else {
                        this.pcrud.search(
                            "cmpcsm", {"ptype_key": working_ptype}, {
                                "order_by": {"cmpcsm": "subfield"},
                                "oncomplete": dojo.hitch(this, function(r) {
                                    if (r = openils.Util.readResponse(r)) {
                                        this._cache.subfields[working_ptype]= r;
                                        callback(r);
                                    } else {
                                        throw new Error(this._.DATA_ERROR_007);
                                    }
                                })
                            }
                        );
                    }
                },
                "_get_values_for_step": function(step, callback) {
                    /* Values are cached by subfield ID, so we find the
                     * current subfield ID using the step and the
                     * working_ptype. */

                    if (this.step == 'a') {
                        callback(this._.A_LABEL, this._cache.types);
                        return;
                    }

                    var step = this.step;   /* for use w/in closure */
                    var working_ptype = this.value.substr(0, 1);
                    var subfields =
                        this._cache.subfields[working_ptype].filter(
                            function(s) { return s.subfield() == step; }
                        );

                    if (subfields.length != 1) {
                        throw new Error(this._.BAD_SUBFIELD_DATA);
                        return;
                    }

                    var subfield = subfields[0];
                    if (this._cache.values[subfield.id()]) {
                        callback(
                            subfield.label(),
                            this._cache.values[subfield.id()]
                        );
                    } else {
                        this.pcrud.search(
                            "cmpcvm", {"ptype_subfield": subfield.id()}, {
                                "order_by": {"cmpcvm": "value"},
                                "onresponse": dojo.hitch(this, function(r) {
                                    if (r = openils.Util.readResponse(r)) {
                                        this._cache.values[subfield.id()] =
                                            r = r.map(
                                                function(v) {
                                                    return [v.value(),v.label()]
                                                }
                                            );
                                        callback(subfield.label(), r);
                                    } else {
                                        throw new Error(this._.DATA_ERROR_007);
                                    }
                                })
                            }
                        );
                    }
                },
                "_get_step_slot": function() {
                    /* We should never need to know the slot for our step
                     * until *after* we have the subfields for that step
                     * loaded. That allows us to keep this function sync
                     * (i.e., it returns instead of using a callback).  */

                    if (this.step == 'a') {
                        return [0, 1];
                    } else {
                        var step = this.step;   /* to use w/in closure */
                        var working_ptype = this.value.substr(0, 1);
                        var matches =
                            this._cache.subfields[working_ptype].filter(
                                function(s) { return s.subfield() == step; }
                            );

                        if (matches.length == 1)
                            return [matches[0].start_pos(),matches[0].length()];
                        else
                            throw new Error(this._.BAD_SUBFIELD_DATA);
                    }
                },
                "_move_step": function(offset) {
                    /* This method is/should only be called when we know we
                     * have the list of subfields for our working_ptype cached.
                     *
                     * We have two jobs in this method:
                     *  1) Set this.step to something new.
                     *  2) Update this.more_forward and this.more_back (bools)
                     */
                    var working_ptype = this.value.substr(0, 1);
                    var found = -1;
                    var sf_list = this._cache.subfields[working_ptype];

                    for (var i = 0; i < sf_list.length; i++) {
                        if (sf_list[i].subfield() == this.step) {
                            found = i;
                            break;
                        }
                    }

                    var idx = found + offset;
                    if (sf_list[idx]) {
                        this.step = sf_list[idx].subfield();
                        this.more_forward = Boolean(sf_list[idx + 1]);
                        this.more_back = Boolean(idx >= 0);
                    } else if (idx == -1) { /* 'a' */
                        this.step = 'a';
                        this.more_back = false;
                        this.more_forward = true; /* or something's broke */
                    } else {
                        throw new Error(this._.FELL_OFF_STEPS);
                    }
                },
                "_update_question_XUL": function(step_label, value_list) {
                    var qh = this.question_holder;

                    while (qh.firstChild) qh.removeChild(qh.firstChild);

                    /* Add question label */
                    var label = document.createElement("label");
                    label.setAttribute("value", step_label + "?");
                    label.setAttribute("style", "min-width: 16em;");
                    qh.appendChild(label);

                    /* Create combobox (in XUL this a <menulist editable="true">
                     * with <menupopup> underneath and several <menuitem>s under
                     * that). */
                    var ml = this.step_user_control =
                        document.createElement("menulist");
                    ml.setAttribute("editable", "true");
                    var mp = document.createElement("menupopup");
                    ml.appendChild(mp);

                    var starting_value = this.get_step_value();
                    var found_starting_value = false;

                    value_list.forEach(
                        function(v) {
                            var mi = document.createElement("menuitem");
                            mi.setAttribute("label", v[0] + ": " + v[1]);
                            mi.setAttribute("value", v[0]);

                            if (v[0] == starting_value) {
                                mi.setAttribute("selected", "true");
                                found_starting_value = true;
                            }

                            mp.appendChild(mi);
                        }
                    );

                    if (!found_starting_value) {
                        /* Starting value wasn't one of the menuitems, but
                         * we can force it: */
                        ml.setAttribute("label", starting_value);
                    }
                    qh.appendChild(ml);
                },
                "_update_value_label_XUL": function(step_win, value) {
                    var before = value.substr(0, step_win[0]);
                    var within = value.substr(step_win[0], step_win[1]);
                    var after = value.substr(step_win[0] + step_win[1]);

                    var div = this.value_label;
                    while (div.firstChild)
                        div.removeChild(div.firstChild);

                    div.appendChild(document.createTextNode(before));

                    var el = document.createElementNS(_xhtml_ns,"xhtml:strong");
                    el.appendChild(document.createTextNode(within));
                    div.appendChild(el);

                    div.appendChild(document.createTextNode(after));
                },
                "_gen_XUL_oncommand": function(methstr) {
                    return "try { " + this.outside_ref +
                        "." + methstr + " } catch (E) { alert('" +
                        this.outside_ref + ": ' + E) }";
                },
                "_build_XUL": function() {
                    var vbox = this.container_node.appendChild(
                        document.createElement("vbox")
                    );
                    vbox.setAttribute( "style", "cursor: default;" );

                    var top_hbox =
                        vbox.appendChild(document.createElement("hbox"));

                    this.question_holder =
                        vbox.appendChild(document.createElement("hbox"));
                    this.question_holder.setAttribute("align", "center");

                    var bottom_hbox =
                        vbox.appendChild(document.createElement("hbox"));

                    this.value_label = top_hbox.appendChild(
                        document.createElementNS(_xhtml_ns, "xhtml:div")
                    );

                    /* These em's must be measured in terms of the body
                     * font-size, not the font-size local to these elements?
                     * Or is that how em's always work? */
                    this.value_label.setAttribute(
                        "style", "min-width: 16em; white-space: pre;"
                    );

                    /* From here to the end of the method we're just building
                     * and placing the wizard's four buttons. */
                    var button;

                    button = document.createElement("button");
                    button.setAttribute("label", this._.OK);
                    button.setAttribute("icon", "apply");
                    button.setAttribute(
                        "oncommand", this._gen_XUL_oncommand("apply()")
                    );
                    top_hbox.appendChild(button);

                    button = document.createElement("button");
                    button.setAttribute("label", this._.CANCEL);
                    button.setAttribute("icon", "cancel");
                    button.setAttribute(
                        "oncommand", this._gen_XUL_oncommand("cancel()")
                    );
                    top_hbox.appendChild(button);

                    this.back_button = button =
                        document.createElement("button");
                    button.setAttribute("label", this._.BACK);
                    button.setAttribute("icon", "go-back");
                    button.setAttribute(
                        "oncommand", this._gen_XUL_oncommand("move(-1)")
                    );
                    button.disabled = true;
                    bottom_hbox.appendChild(button);

                    this.forward_button = button =
                        document.createElement("button");
                    button.setAttribute("label", this._.FORWARD);
                    button.setAttribute("icon", "go-forward");
                    button.setAttribute(
                        "oncommand", this._gen_XUL_oncommand("move(1)")
                    );
                    button.disabled = true;
                    bottom_hbox.appendChild(button);

                    /* Save reference to root node of wizard for easy
                     * removal when finished. */
                    this.wizard_root_node = vbox;
                }
            }
        );
    })();

    /* Class-wide cache; all instance objects share this */
    openils.widget.PhysCharWizard.cache = {
        "subfields": {},    /* by type */
        "values": {},       /* by subfield ID */
        "types": []
    };

    openils.widget.PhysCharWizard.localeStrings =
        dojo.i18n.getLocalization("openils.widget", "PhysCharWizard");
}

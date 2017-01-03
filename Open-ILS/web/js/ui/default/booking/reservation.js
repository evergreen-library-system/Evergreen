/*
 * Details, details...
 */
dojo.require("fieldmapper.OrgUtils");
dojo.require("openils.PermaCrud");
dojo.require("openils.User");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.require("dojo.data.ItemFileReadStore");
dojo.require("dijit.form.DateTextBox");
dojo.require("dijit.form.TimeTextBox");
dojo.require("dojo.date.stamp");
dojo.requireLocalization("openils.booking", "reservation");

/*
 * Globals; prototypes and their instances
 */
var localeStrings = dojo.i18n.getLocalization("openils.booking", "reservation");
var pcrud = new openils.PermaCrud();
var opts;
var our_brt;
var pickup_lib_selected;
var brt_list = [];
var brsrc_index = {};
var bresv_index = {};
var just_reserved_now = {};
var aous_cache = {};

function AttrValueTable() { this.t = {}; }
AttrValueTable.prototype.set = function(attr, value) { this.t[attr] = value; };
AttrValueTable.prototype.update_from_selector = function(selector) {
    var attr  = selector.name.match(/_(\d+)$/)[1];
    var value = selector.options[selector.selectedIndex].value;
    if (attr)
        attr_value_table.set(attr, value);
};
AttrValueTable.prototype.get_all_values = function() {
    var values = [];
    for (var k in this.t) {
        if (this.t[k] != undefined && this.t[k] != "")
            values.push(this.t[k]);
    }
    return values;
};
var attr_value_table =  new AttrValueTable();

function TimestampRange() {
    this.start = new Date();
    this.end = new Date();

    this.validity = {"start": false, "end": false};
    this.nodes = {
        "start": {"date": undefined, "time": undefined},
        "end": {"date": undefined, "time": undefined}
    };
    this.saved_style_properties = {};
    this.invalid_style_properties = {
        "backgroundColor": "#ffcccc",
        "color": "#990000",
        "borderColor": "#990000",
        "fontWeight": "bold"
    };
}
TimestampRange.prototype.get_timestamp = function(when) {
    return dojo.date.stamp.toISOString(this[when]).
        replace("T", " ").substr(0, 19);
};
TimestampRange.prototype.get_range = function() {
    return this.is_backwards() ?
        [this.get_timestamp("end"), this.get_timestamp("start")] :
        [this.get_timestamp("start"), this.get_timestamp("end")];
};
TimestampRange.prototype.update_from_widget = function(widget) {
    var when = widget.name.match(/(start|end)/)[1];
    var which = widget.name.match(/(date|time)/)[1];

    if (this.nodes[when][which] == undefined)
        this.nodes[when][which] = widget.domNode; /* We'll need this later */

    if (when && which) {
        this.update_timestamp(when, which, widget.attr("value"));
    }

    this.compute_validity();
    this.paint_validity();
};
TimestampRange.prototype.compute_validity = function() {
    if (Math.abs(this.start - this.end) < 1000) {
        this.validity.end = false;
    } else {
        if (this.start < this.current_minimum())
            this.validity.start = false;
        else
            this.validity.start = true;

        if (this.end < this.current_minimum())
            this.validity.end = false;
        else
            this.validity.end = true;
    }
};
/* This method provides the minimum timestamp that is considered valid. For
 * now it's arbitrarily "now + 15 minutes", meaning that all reservations
 * must be made at least 15 minutes in the future.
 *
 * For reasons of keeping the middle layer happy, this should always return
 * a time that is at least somewhat in the future. The ML isn't able to target
 * any resources for a reservation with a start date that isn't in the future.
 */
TimestampRange.prototype.current_minimum = function() {
    /* XXX This is going to be a problem with local clocks that are off. */
    var n = new Date();
    n.setTime(n.getTime() + 1000 * 900); /* XXX 15 minutes; stop hardcoding! */
    return n;
};
TimestampRange.prototype.update_timestamp = function(when, which, value) {
    if (which == "date") {
        this[when].setFullYear(value.getFullYear());
        /* month and date MUST be done together */
        this[when].setMonth(value.getMonth(), value.getDate());
    } else {    /* "time" */
        this[when].setHours(value.getHours());
        this[when].setMinutes(value.getMinutes());
        this[when].setSeconds(0);
    }
};
TimestampRange.prototype.is_backwards = function() {
    return (this.start > this.end);
};
TimestampRange.prototype.paint_validity = function()  {
    for (var when in this.validity) {
        if (this.validity[when]) {
            this.paint_valid_node(this.nodes[when].date);
            this.paint_valid_node(this.nodes[when].time);
        } else {
            this.paint_invalid_node(this.nodes[when].date);
            this.paint_invalid_node(this.nodes[when].time);
        }
    }
};
TimestampRange.prototype.paint_invalid_node = function(node) {
    if (node) {
        /* Just toggling the class of something would be better than
         * manually setting style here, but I haven't been able to get that
         * to play nicely with dojo's styling of the date/time textboxen.
         */
        if (this.saved_style_properties.backgroundColor == undefined) {
            for (var k in this.invalid_style_properties) {
                this.saved_style_properties[k] = node.style[k];
            }
        }
        for (var k in this.invalid_style_properties) {
            node.style[k] = this.invalid_style_properties[k];
        }
    }
};
TimestampRange.prototype.paint_valid_node = function(node) {
    if (node) {
        for (var k in this.saved_style_properties) {
            node.style[k] = this.saved_style_properties[k];
        }
    }
};
TimestampRange.prototype.is_valid = function() {
    return (this.validity.start && this.validity.end);
};
var reserve_timestamp_range = new TimestampRange();

function SelectorMemory(selector) {
    this.selector = selector;
    this.memory = {};
}
SelectorMemory.prototype.save = function() {
    for (var i = 0; i < this.selector.options.length; i++) {
        if (this.selector.options[i].selected) {
            this.memory[this.selector.options[i].value] = true;
        }
    }
};
SelectorMemory.prototype.restore = function() {
    for (var i = 0; i < this.selector.options.length; i++) {
        if (this.memory[this.selector.options[i].value]) {
            if (!this.selector.options[i].disabled)
                this.selector.options[i].selected = true;
        }
    }
};

/*
 * These functions communicate with the middle layer.
 */
function get_all_noncat_brt() {
    return pcrud.search("brt",
        {"id": {"!=": null}, "catalog_item": "f"},
        {"order_by": {"brt":"name"}}
    );
}

function get_brt_by_id(id) {
    return pcrud.retrieve("brt", id);
}

function get_brsrc_id_list() {
    var options = {"type": our_brt.id(), "pickup_lib": pickup_lib_selected};

    /* This mechanism for avoiding the passing of an empty 'attribute_values'
     * option is essential because if you pass such an option to the
     * middle layer API at all, it won't return any IDs for brsrcs that
     * don't have at least one attribute of some kind.
     */
    var attribute_values = attr_value_table.get_all_values();
    if (attribute_values.length > 0)
        options.attribute_values = attribute_values;

    options.available = reserve_timestamp_range.get_range();

    return fieldmapper.standardRequest(
        ["open-ils.booking", "open-ils.booking.resources.filtered_id_list"],
        [openils.User.authtoken, options]
    );
}

/* FIXME: We need failure checking after pcrud.retrieve() */
function add_brsrc_to_index_if_needed(list, further) {
    for (var i in list) {
        if (!brsrc_index[list[i]]) {
            brsrc_index[list[i]] = pcrud.retrieve("brsrc", list[i]);
        }
        if (further)
            further(brsrc_index[list[i]]);
    }
}

function sync_brsrc_index_from_ids(available_list, additional_list) {
    /* Default states for everything in the index. Read the further comments. */
    for (var i in brsrc_index) {
        brsrc_index[i].isdeleted(true);
        brsrc_index[i].ischanged(false);
    }

    /* Populate the cache with anything that's missing and tag everything
     * in the "available" list as *not* deleted, and tag everything in the
     * additional list as "changed." See below. */
    add_brsrc_to_index_if_needed(
        available_list, function(o) { o.isdeleted(false); }
    );
    add_brsrc_to_index_if_needed(
        additional_list,
        function(o) {
            if (!(o.id() in just_reserved_now)) o.ischanged(true);
        }
    );
    /* NOTE: We lightly abuse the isdeleted() and ischanged() magic fieldmapper
     * attributes of the brsrcs in our cache.  Because we're not going to
     * pass back any brsrcs to the middle layer, it doesn't really matter
     * what we set this attribute to. What we're using it for is to indicate
     * in our little brsrc cache how a given brsrc should be displayed in this
     * UI's current state (based on whether the brsrc matches timestamp range
     * availability (isdeleted(false)) and whether the brsrc has been forced
     * into the list because it was selected in a previous interface (like
     * the catalog) (ischanged(true))).
     */
}

function check_bresv_targeting(results) {
    var missing = 0;
    var due_dates = [];
    for (var i in results) {
        var targ = results[i].targeting;
        if (!(targ && targ.current_resource)) {
            missing++;
            if (targ) {
                if (targ.error == "NO_COPIES" && targ.conflicts) {
                    for (var k in targ.conflicts) {
                        /* Could potentially get more circ information from
                         * targ.conflicts for display in the future. */
                        due_dates.push(humanize_timestamp_string2(targ.conflicts[k].due_date()));
                    }
                }
            }
        } else {
            just_reserved_now[results[i].targeting.current_resource] = true;
        }
    }
    return {"missing": missing, "due_dates": due_dates};
}

function create_bresv(resource_list) {
    var barcode = document.getElementById("patron_barcode").value;
    if (barcode == "") {
        alert(localeStrings.WHERES_THE_BARCODE);
        return;
    } else if (!reserve_timestamp_range.is_valid()) {
        alert(localeStrings.INVALID_TS_RANGE);
        return;
    }
    var email_notify = document.getElementById("email_notify").checked ? true : false;
    var results;
    try {
        results = fieldmapper.standardRequest(
            ["open-ils.booking", "open-ils.booking.reservations.create"],
            [
                openils.User.authtoken,
                barcode,
                reserve_timestamp_range.get_range(),
                pickup_lib_selected,
                our_brt.id(),
                resource_list,
                attr_value_table.get_all_values(),
                email_notify
            ]
        );
    } catch (E) {
        alert(localeStrings.CREATE_BRESV_LOCAL_ERROR + E);
    }
    if (results) {
        if (is_ils_event(results)) {
            if (is_ils_actor_card_error(results)) {
                alert(localeStrings.ACTOR_CARD_NOT_FOUND);
            } else {
                alert(my_ils_error(
                    localeStrings.CREATE_BRESV_SERVER_ERROR, results
                ));
            }
        } else {
            var targeting = check_bresv_targeting(results);
            if (targeting.missing) {
                if (aous_cache["booking.require_successful_targeting"]) {
                    alert(
                        dojo.string.substitute(
                            localeStrings.CREATE_BRESV_OK_MISSING_TARGET,
                                [results.length, targeting.missing]
                        ) + "\n\n" +
                        dojo.string.substitute(
                            localeStrings.CREATE_BRESV_OK_MISSING_TARGET_BLOCKED_BY_CIRC,
                                [targeting.due_dates]
                        ) + "\n\n" +
                        localeStrings.CREATE_BRESV_OK_MISSING_TARGET_WILL_CANCEL
                    );
                    cancel_reservations(
                        results.map(
                            function(o) { return o.bresv; },
                            true /* skip_update */
                        )
                    );
                } else {
                    alert(
                        dojo.string.substitute(
                            localeStrings.CREATE_BRESV_OK_MISSING_TARGET,
                                [results.length, targeting.missing]
                        ) + "\n\n" +
                        dojo.string.substitute(
                            localeStrings.CREATE_BRESV_OK_MISSING_TARGET_BLOCKED_BY_CIRC,
                                [targeting.due_dates]
                        )
                    );
                }
            } else {
                alert(
                    dojo.string.substitute(
                        localeStrings.CREATE_BRESV_OK, [results.length]
                    )
                );
            }
            update_brsrc_list();
            update_bresv_grid();
        }
    } else {
        alert(localeStrings.CREATE_BRESV_SERVER_NO_RESPONSE);
    }
}

function flatten_to_dojo_data(obj_list) {
    return {
        "label": "id",
        "identifier": "id",
        "items": obj_list.map(function(o) {
            var new_obj = {
                "id": o.id(),
                "type": o.target_resource_type().name(),
                "start_time": humanize_timestamp_string(o.start_time()),
                "end_time": humanize_timestamp_string(o.end_time())
            };

            if (o.current_resource())
                new_obj["resource"] = o.current_resource().barcode();
            else if (o.target_resource())
                new_obj["resource"] = "* " + o.target_resource().barcode();
            else
                new_obj["resource"] = "* " + localeStrings.UNTARGETED + " *";
            return new_obj;
        })
    };
}

function create_bresv_on_brsrc() {
    var selector = document.getElementById("brsrc_list");
    var selected_values = [];
    for (var i in selector.options) {
        if (selector.options[i] && selector.options[i].selected)
            selected_values.push(selector.options[i].value);
    }
    if (selected_values.length > 0)
        create_bresv(selected_values);
    else
        alert(localeStrings.SELECT_A_BRSRC_THEN);
}

function create_bresv_on_brt() {
    if (any_usable_brsrc())
        create_bresv();
    else
        alert(localeStrings.NO_USABLE_BRSRC);
}

function get_actor_by_barcode(barcode) {
    var usr = fieldmapper.standardRequest(
        ["open-ils.actor", "open-ils.actor.user.fleshed.retrieve_by_barcode"],
        [openils.User.authtoken, barcode]
    );
    if (usr == null) {
        alert(localeStrings.GET_PATRON_NO_RESULT);
    } else if (is_ils_event(usr)) {
        return null; /* XXX inelegant: this function is quiet about errors
                        here because to report them would be redundant with
                        another function that gets called right after this one.
                      */
    } else {
        return usr;
    }
}

function init_bresv_grid(barcode) {
    var result = fieldmapper.standardRequest(
        ["open-ils.booking",
            "open-ils.booking.reservations.filtered_id_list"
        ],
        [openils.User.authtoken, {
            "user_barcode": barcode,
            "fields": {
                "pickup_time": null,
                "cancel_time": null,
                "return_time": null
            }
        }, /* whole_obj */ true]
    );
    if (result == null) {
        set_datagrid_empty_store(bresvGrid, flatten_to_dojo_data);
        alert(localeStrings.GET_BRESV_LIST_NO_RESULT);
    } else if (is_ils_event(result)) {
        set_datagrid_empty_store(bresvGrid, flatten_to_dojo_data);
        if (is_ils_actor_card_error(result)) {
            alert(localeStrings.ACTOR_CARD_NOT_FOUND);
        } else {
            alert(my_ils_error(localeStrings.GET_BRESV_LIST_ERR, result));
        }
    } else {
        if (result.length < 1) {
            document.getElementById("bresv_grid_alt_explanation").innerHTML =
                localeStrings.NO_EXISTING_BRESV;
            hide_dom_element(document.getElementById("bresv_grid"));
            reveal_dom_element(document.getElementById("reserve_under"));
        } else {
            document.getElementById("bresv_grid_alt_explanation").innerHTML =
                "";
            reveal_dom_element(document.getElementById("bresv_grid"));
            reveal_dom_element(document.getElementById("reserve_under"));
        }
        /* May as well do the following in either case... */
        bresvGrid.setStore(
            new dojo.data.ItemFileReadStore(
                {"data": flatten_to_dojo_data(result)}
            )
        );
        bresv_index = {};
        for (var i in result) {
            bresv_index[result[i].id()] = result[i];
        }
    }
}

function cancel_reservations(bresv_id_list, skip_update) {
    try {
        var result = fieldmapper.standardRequest(
            ["open-ils.booking", "open-ils.booking.reservations.cancel"],
            [openils.User.authtoken, bresv_id_list]
        );
    } catch (E) {
        alert(localeStrings.CXL_BRESV_FAILURE2 + E);
        return;
    }
    if (!skip_update) setTimeout(update_bresv_grid, 0);
    if (!result) {
        alert(localeStrings.CXL_BRESV_FAILURE);
    } else if (is_ils_event(result)) {
        alert(my_ils_error(localeStrings.CXL_BRESV_FAILURE2, result));
    } else {
        alert(
            dojo.string.substitute(
                localeStrings.CXL_BRESV_SUCCESS, [result.length]
            )
        );
    }
}

function munge_specific_resource(barcode) {
    try {
        var copy_list = pcrud.search(
            "acp", {"barcode": barcode, "deleted": "f"}
        );
        if (copy_list && copy_list.length > 0) {
            var r = fieldmapper.standardRequest(
                ["open-ils.booking",
                    "open-ils.booking.resources.create_from_copies"],
                [openils.User.authtoken,
                    copy_list.map(function(o) { return o.id(); })]
            );

            if (!r) {
                alert(localeStrings.ON_FLY_NO_RESPONSE);
            } else if (is_ils_event(r)) {
                alert(my_ils_error(localeStrings.ON_FLY_ERROR, r));
            } else {
                if (!(our_brt = get_brt_by_id(r.brt[0][0]))) {
                    alert(localeStrings.COULD_NOT_RETRIEVE_BRT_PASSED_IN);
                } else {
                    opts.booking_results = r;
                    init_reservation_interface();
                }
            }
        } else {
            alert(localeStrings.BRSRC_NOT_FOUND);
        }
    } catch (E) {
        alert(localeStrings.BRSRC_RETRIEVE_ERROR + E);
    }
}

/*
 * These functions deal with interface tricks (populating widgets,
 * changing the page, etc.).
 */
function init_pickup_lib_selector() {
    var User = new openils.User();
    User.buildPermOrgSelector(
        "ADMIN_BOOKING_RESERVATION", pickup_lib_selector, null,
        function() {
            pickup_lib_selected = pickup_lib_selector.getValue();
            dojo.connect(pickup_lib_selector, "onChange",
                function() {
                    pickup_lib_selected = this.getValue();
                    update_brsrc_list();
                }
            )
        }
    );
}

function provide_brt_selector(targ_div) {
    if (!targ_div) {
        alert(localeStrings.NO_TARG_DIV);
    } else {
        brt_list = get_all_noncat_brt();
        if (!brt_list || brt_list.length < 1) {
            document.getElementById("select_noncat_brt_block").
                style.display = "none";
        } else {
            var selector = document.createElement("select");
            selector.setAttribute("id", "brt_selector");
            selector.setAttribute("name", "brt_selector");
            /* I'm reluctantly hardcoding this "size" attribute as 8
             * because you can't accomplish this with CSS anyway.
             */
            selector.setAttribute("size", 8);
            for (var i in brt_list) {
                var option = document.createElement("option");
                option.setAttribute("value", brt_list[i].id());
                option.appendChild(document.createTextNode(brt_list[i].name()));
                selector.appendChild(option);
            }
            targ_div.innerHTML = "";
            targ_div.appendChild(selector);
        }
    }
}

function init_resv_iface_arb() {
    init_reservation_interface(document.getElementById("arbitrary_resource"));
}

function init_resv_iface_sel() {
    init_reservation_interface(document.getElementById("brt_selector"));
}

function init_reservation_interface(widget) {
    /* Show or hide the email notification checkbox depending on org unit setting. */
    if (!aous_cache["booking.allow_email_notify"]) {
        hide_dom_element(document.getElementById("contain_email_notify"));
    }
    /* Save a global reference to the brt we're going to reserve */
    if (widget && (widget.selectedIndex != undefined)) {
        our_brt = brt_list[widget.selectedIndex];
    } else if (widget != undefined) {
        if (!munge_specific_resource(widget.value))
            return;
    }

    /* Hide and reveal relevant divs. */
    var search_block = document.getElementById("brt_search_block");
    var reserve_block = document.getElementById("brt_reserve_block");
    hide_dom_element(search_block);
    reveal_dom_element(reserve_block);

    /* Get a list of attributes that can apply to that brt. */
    var bra_list = pcrud.search("bra", {"resource_type": our_brt.id()});
    if (!bra_list) {
        alert(localeString.NO_BRA_LIST);
        return;
    }

    /* Get a table of values that can apply to the above attributes. */
    var brav_by_bra = {};
    bra_list.map(function(o) {
        brav_by_bra[o.id()] = pcrud.search("brav", {"attr": o.id()});
    });

    /* Hide the label over the attributes widgets if we have nothing to show. */
    var domf = (bra_list.length < 1) ? hide_dom_element : reveal_dom_element;
    domf(document.getElementById("bra_and_brav_header"));

    /* Create DOM widgets to represent each attribute/values set. */
    for (var i in bra_list) {
        var bra_div = document.createElement("div");
        bra_div.setAttribute("class", "nice_vertical_padding");

        var bra_select = document.createElement("select");
        bra_select.setAttribute("name", "bra_" + bra_list[i].id());
        bra_select.setAttribute(
            "onchange",
            "attr_value_table.update_from_selector(this); update_brsrc_list();"
        );

        var bra_opt_any = document.createElement("option");
        bra_opt_any.appendChild(document.createTextNode(localeStrings.ANY));
        bra_opt_any.setAttribute("value", "");

        bra_select.appendChild(bra_opt_any);

        var bra_label = document.createElement("label");
        bra_label.setAttribute("class", "bra");
        bra_label.appendChild(document.createTextNode(bra_list[i].name()));

        var j = bra_list[i].id();
        for (var k in brav_by_bra[j]) {
            var bra_opt = document.createElement("option");
            bra_opt.setAttribute("value", brav_by_bra[j][k].id());
            bra_opt.appendChild(
                document.createTextNode(brav_by_bra[j][k].valid_value())
            );
            bra_select.appendChild(bra_opt);
        }

        bra_div.appendChild(bra_label);
        bra_div.appendChild(bra_select);
        document.getElementById("bra_and_brav").appendChild(bra_div);
    }
    /* Add a prominent label reminding the user what resource type they're
     * asking about. */
    document.getElementById("brsrc_list_header").innerHTML = our_brt.name();
    init_pickup_lib_selector();
    update_brsrc_list();
}

function update_brsrc_list() {
    var brsrc_id_list = get_brsrc_id_list();
    var force_list = (opts.booking_results && opts.booking_results.brsrc) ?
        opts.booking_results.brsrc.map(function(o) { return o[0]; }) : [];

    sync_brsrc_index_from_ids(brsrc_id_list, force_list);

    var target_selector = document.getElementById("brsrc_list");
    var selector_memory = new SelectorMemory(target_selector);
    selector_memory.save();
    target_selector.innerHTML = "";

    for (var i in brsrc_index) {
        if (brsrc_index[i].isdeleted() && (!brsrc_index[i].ischanged()))
            continue;

        var opt = document.createElement("option");
        opt.setAttribute("value", brsrc_index[i].id());
        opt.appendChild(document.createTextNode(brsrc_index[i].barcode()));

        if (brsrc_index[i].isdeleted() && (brsrc_index[i].ischanged())) {
            opt.setAttribute("class", "forced_unavailable");
            opt.setAttribute("disabled", "disabled");
        }

        target_selector.appendChild(opt);
    }

    selector_memory.restore();
}

function any_usable_brsrc() {
    for (var i in brsrc_index) {
        if (!brsrc_index[i].isdeleted())
            return true;
    }
    return false;
}

function update_bresv_grid() {
    var widg = document.getElementById("patron_barcode");
    if (widg.value != "") {
        setTimeout(function() {
            var target = document.getElementById(
                "existing_reservation_patron_line"
            );
            var patron = get_actor_by_barcode(widg.value);
            if (patron) {
                target.innerHTML = (
                    localeStrings.HERE_ARE_EXISTING_BRESV + " " +
                    formal_name(patron) + ": "
                );
            } else {
                target.innerHTML = "";
            }
        }, 0);
        setTimeout(function() { init_bresv_grid(widg.value); }, 0);
    }
}

function init_timestamp_widgets() {
    var when = ["start", "end"];
    for (var i in when) {
        reserve_timestamp_range.update_from_widget(
            new dijit.form.TimeTextBox({
                name: "reserve_time_" + when[i],
                value: new Date(),
                constraints: {
                    timePattern: "HH:mm",
                    clickableIncrement: "T00:15:00",
                    visibleIncrement: "T00:15:00",
                    visibleRange: "T01:30:00"
                },
                onChange: function() {
                    reserve_timestamp_range.update_from_widget(this);
                    update_brsrc_list();
                }
            }, "reserve_time_" + when[i])
        );
        reserve_timestamp_range.update_from_widget(
            new dijit.form.DateTextBox({
                name: "reserve_date_" + when[i],
                value: new Date(),
                onChange: function() {
                    reserve_timestamp_range.update_from_widget(this);
                    update_brsrc_list();
                }
            }, "reserve_date_" + when[i])
        );
    }
}

function cancel_selected_bresv(bresv_dojo_items) {
    if (bresv_dojo_items && bresv_dojo_items.length > 0 &&
        (bresv_dojo_items[0].length == undefined ||
            bresv_dojo_items[0].length > 0)) {
        cancel_reservations(
            bresv_dojo_items.map(function(o) { return o.id[0]; })
        );
        /* After some delay to allow the cancellations a chance to get
         * committed, refresh the brsrc list as it might reflect newly
         * available resources now. */
        if (our_brt) setTimeout(update_brsrc_list, 2000);
    } else {
        alert(localeStrings.CXL_BRESV_SELECT_SOMETHING);
    }
}

/* The following function should return true if the reservation interface
 * should start normally (show a list of brt to choose from) or false if
 * it should not (because we've "started" it some other way by setting up
 * and displaying other widgets).
 */
function early_action_passthru() {
    if (opts.booking_results) {
        if (opts.booking_results.brt.length != 1) {
            alert(localeStrings.NEED_EXACTLY_ONE_BRT_PASSED_IN);
            return true;
        } else if (!(our_brt = get_brt_by_id(opts.booking_results.brt[0][0]))) {
            alert(localeStrings.COULD_NOT_RETRIEVE_BRT_PASSED_IN);
            return true;
        }

        init_reservation_interface();
        return false;
    }

    var uri = location.href;
    var query = uri.substring(uri.indexOf("?") + 1, uri.length);
    var queryObject = dojo.queryToObject(query);
    if (typeof queryObject['patron_barcode'] != 'undefined') {
        opts.patron_barcode = queryObject['patron_barcode'];
    }

    if (opts.patron_barcode) {
        document.getElementById("contain_patron_barcode").style.display="none";
        document.getElementById("patron_barcode").value = opts.patron_barcode;
        update_bresv_grid();
    }

    return true;
}

function init_aous_cache() {
    /* The following method call could be given a longer
     * list of OU settings to fetch in the future if needed. */
    var results = fieldmapper.aou.fetchOrgSettingBatch(
        openils.User.user.ws_ou(), ["booking.require_successful_targeting", "booking.allow_email_notify"]
    );
    if (results && !is_ils_event(results)) {
        for (var k in results) {
            if (results[k] != undefined)
                aous_cache[k] = results[k].value;
        }
    } else if (results) {
        alert(my_ils_error(localeStrings.ERROR_FETCHING_AOUS, results));
    } else {
        alert(localeStrings.ERROR_FETCHING_AOUS);
    }
}

/*
 * my_init
 */
function my_init() {
    hide_dom_element(document.getElementById("brt_reserve_block"));
    reveal_dom_element(document.getElementById("brt_search_block"));
    hide_dom_element(document.getElementById("reserve_under"));
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));
    init_aous_cache();
    init_timestamp_widgets();

    setTimeout(
        function() {
            if (typeof xulG != 'undefined' && typeof xulG.bresv_interface_opts != 'undefined') {
                opts = xulG.bresv_interface_opts;
            } else {
                opts = {};
            }
            if (early_action_passthru())
                provide_brt_selector(document.getElementById("brt_selector_here"));
        }, 0
    );
}

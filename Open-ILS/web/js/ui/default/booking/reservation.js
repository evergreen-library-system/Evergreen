/*
 * Details, details...
 */
dojo.require("fieldmapper.OrgUtils");
dojo.require("openils.PermaCrud");
dojo.require("dojo.data.ItemFileReadStore");
dojo.require("dijit.form.DateTextBox");
dojo.require("dijit.form.TimeTextBox");
dojo.requireLocalization("openils.booking", "reservation");

/*
 * Globals; prototypes and their instances
 */
var localeStrings = dojo.i18n.getLocalization("openils.booking", "reservation");
var pcrud = new openils.PermaCrud();
var our_brt;
var brsrc_index = {};
var bresv_index = {};

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
    this.start = {"date": undefined, "time": undefined};
    this.end = {"date": undefined, "time": undefined};
}
TimestampRange.prototype.get_timestamp = function(when) {
    return (this[when].date + " " + this[when].time);
};
TimestampRange.prototype.get_range = function() {
    return this.is_backwards() ?
        [this.get_timestamp("end"), this.get_timestamp("start")] :
        [this.get_timestamp("start"), this.get_timestamp("end")];
};
TimestampRange.prototype.split_time = function(s) {
    /* We're not interested in seconds for our purposes,
     * so we floor everything to :00.
     *
     * Also, notice that following discards all time zone information
     * from the timestamp string represenation.  This should probably
     * stay the way it is, even when this code is improved to support
     * selecting time zones (it currently just assumes server's local
     * time).  The easy way to add support will be to add a drop-down
     * selector from which the user can pick a time zone, then use
     * that timezone literal in an "AT TIME ZONE" clause in SQL on
     * the server side.
     */
    return s.split("T")[1].replace(/(\d{2}:\d{2}:)(\d{2})(.*)/, "$100");
};
TimestampRange.prototype.split_date = function(s) {
    return s.split("T")[0];
};
TimestampRange.prototype.update_from_widget = function(widget) {
    var when = widget.id.match(/(start|end)/)[1];
    var which = widget.id.match(/(date|time)/)[1];

    if (when && which) {
        this[when][which] =
            this["split_" + which](widget.serialize(widget.value));
    }
};
TimestampRange.prototype.is_backwards = function() {
    return (this.get_timestamp("start") > this.get_timestamp("end"));
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
            this.selector.options[i].selected = true;
        }
    }
};

/*
 * Misc helper functions
 */
function hide_dom_element(e) { e.style.display = "none"; };
function reveal_dom_element(e) { e.style.display = ""; };
function get_keys(L) { var K = []; for (var k in L) K.push(k); return K; }
function formal_name(u) {
    var name = u.family_name() + ", " + u.first_given_name();
    if (u.second_given_name())
        name += (" " + u.second_given_name());
    return name;
}
function humanize_timestamp_string(ts) {
    /* For now, this discards time zones. */
    var parts = ts.split("T");
    var timeparts = parts[1].split("-")[0].split(":");
    return parts[0] + " " + timeparts[0] + ":" + timeparts[1];
}
function set_datagrid_empty_store(grid) {
    grid.setStore(
        new dojo.data.ItemFileReadStore(
            {"data": flatten_to_dojo_data([])}
        )
    );
}
function is_ils_error(e) { return (e.ilsevent != undefined); }
function is_ils_actor_card_error(e) {
    return (e.textcode == "ACTOR_CARD_NOT_FOUND");
}
function my_ils_error(header, e) {
    var s = header + "\n";
    var keys = [
        "ilsevent", "desc", "textcode", "servertime", "pid", "stacktrace"
    ];
    for (var i in keys) {
        if (e[keys[i]]) s += ("\t" + keys[i] + ": " + e[keys[i]] + "\n");
    }
    return s;
}

/*
 * These functions communicate with the middle layer.
 */
function get_all_noncat_brt() {
    return pcrud.search("brt",
        {"id": {"!=": null}, "catalog_item": "f"},
        {"order_by": {"brt":"name"}}
    );
}

function get_brsrc_id_list() {
    var options = {"type": our_brt.id()};

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
        [xulG.auth.session.key, options]
    );
}

// FIXME: We need failure checking after pcrud.retrieve()
function sync_brsrc_index_from_ids(id_list) {
    /* One pass to populate the cache with anything that's missing. */
    for (var i in id_list) {
        if (!brsrc_index[id_list[i]]) {
            brsrc_index[id_list[i]] = pcrud.retrieve("brsrc", id_list[i]);
        }
        brsrc_index[id_list[i]].isdeleted(false); // See NOTE below.
    }
    /* A second pass to indicate any entries in the cache to be hidden. */
    for (var i in brsrc_index) {
        if (id_list.indexOf(Number(i)) < 0) { // Number() is important.
            brsrc_index[i].isdeleted(true); // See NOTE below.
        }
    }
    /* NOTE: We lightly abuse the isdeleted() magic attribute of the brsrcs
     * in our cache.  Because we're not going to pass back any brsrcs to
     * the middle layer, it doesn't really matter what we set this attribute
     * to. What we're using it for is to indicate in our little brsrc cache
     * whether a given brsrc should be displayed in this UI's current state
     * (based on whether it was returned by the last call to the middle layer,
     * i.e., whether it matches the currently selected attributes).
     */
}

function check_bresv_targeting(results) {
    var missing = 0;
    for (var i in results) {
        if (!(results[i].targeting && results[i].targeting.current_resource))
            missing++;
    }
    return missing;
}

function create_bresv(resource_list) {
    var barcode = document.getElementById("patron_barcode").value;
    if (barcode == "") {
        alert(localeStrings.WHERES_THE_BARCODE);
        return;
    }
    var results;
    try {
        results = fieldmapper.standardRequest(
            ["open-ils.booking", "open-ils.booking.reservations.create"],
            [
                xulG.auth.session.key,
                barcode,
                reserve_timestamp_range.get_range(),
                our_brt.id(),
                resource_list,
                attr_value_table.get_all_values()
            ]
        );
    } catch (E) {
        alert(localeStrings.CREATE_BRESV_LOCAL_ERROR + E);
    }
    if (results) {
        if (is_ils_error(results)) {
            if (is_ils_actor_card_error(results)) {
                alert(localeStrings.ACTOR_CARD_NOT_FOUND);
            } else {
                alert(my_ils_error(
                    localeStrings.CREATE_BRESV_SERVER_ERROR, results
                ));
            }
        } else {
            var missing;
            alert((missing = check_bresv_targeting(results)) ?
                localeStrings.CREATE_BRESV_OK_MISSING_TARGET(
                    results.length, missing
                ) :
                localeStrings.CREATE_BRESV_OK(results.length)
            );
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
                "end_time": humanize_timestamp_string(o.end_time()),
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
        if (selector.options[i].selected)
            selected_values.push(selector.options[i].value);
    }
    if (selected_values.length > 0)
        create_bresv(selected_values);
    else
        alert(localeStrings.SELECT_A_BRSRC_THEN);
}

function create_bresv_on_brt() { create_bresv(); }

function get_actor_by_barcode(barcode) {
    var usr = fieldmapper.standardRequest(
        ["open-ils.actor", "open-ils.actor.user.fleshed.retrieve_by_barcode"],
        [xulG.auth.session.key, barcode]
    );
    if (usr == null) {
        alert(localeStrings.GET_PATRON_NO_RESULT);
    } else if (is_ils_error(usr)) {
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
        [xulG.auth.session.key, {
            "user_barcode": barcode,
            "fields": {
                "pickup_time": null,
                "cancel_time": null,
                "return_time": null
            }
        }, /* whole_obj */ true]
    );
    if (result == null) {
        set_datagrid_empty_store(bresvGrid);
        alert(localeStrings.GET_BRESV_LIST_NO_RESULT);
    } else if (is_ils_error(result)) {
        set_datagrid_empty_store(bresvGrid);
        if (is_ils_actor_card_error(result)) {
            alert(localeStrings.ACTOR_CARD_NOT_FOUND);
        } else {
            alert(my_ils_error(localeStrings.GET_BRESV_LIST_ERR, result));
        }
    } else {
        bresvGrid.setStore(
            new dojo.data.ItemFileReadStore(
                {"data": flatten_to_dojo_data(result)}
            )
        );
        for (var i in result) {
            bresv_index[result[i].id()] = result[i];
        }
    }
}

function cancel_reservations(bresv_list) {
    for (var i in bresv_list) { bresv_list[i].cancel_time("now"); }
    pcrud.update(
        bresv_list, {
            "oncomplete": function() {
                update_bresv_grid();
                alert(localeStrings.CXL_BRESV_SUCCESS(bresv_list.length));
            },
            "onerror": function(o) {
                update_bresv_grid();
                alert(localeStrings.CXL_BRESV_FAILURE + "\n" + o);
            }
        }
    );
}

/*
 * These functions deal with interface tricks (populating widgets,
 * changing the page, etc.).
 */
function provide_brt_selector(targ_div) {
    if (!targ_div) {
        alert(localeStrings.NO_TARG_DIV);
    } else {
        var brt_list = xulG.brt_list = get_all_noncat_brt();
        if (!brt_list || brt_list.length < 1) {
            targ_div.appendChild(
                document.createTextNode(localeStrings.NO_BRT_RESULTS)
            );
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
            targ_div.appendChild(selector);
        }
    }
}

function init_reservation_interface(f) {
    /* Hide and reveal relevant divs. */
    var search_block = document.getElementById("brt_search_block");
    var reserve_block = document.getElementById("brt_reserve_block");
    hide_dom_element(search_block);
    reveal_dom_element(reserve_block);

    /* Save a global reference to the brt we're going to reserve */
    our_brt = xulG.brt_list[f.brt_selector.selectedIndex];

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

    update_brsrc_list();
}

function update_brsrc_list() {
    var brsrc_id_list = get_brsrc_id_list();
    sync_brsrc_index_from_ids(brsrc_id_list);

    var target_selector = document.getElementById("brsrc_list");
    var selector_memory = new SelectorMemory(target_selector);
    selector_memory.save();
    target_selector.innerHTML = "";

    for (var i in brsrc_index) {
        if (brsrc_index[i].isdeleted()) {
            continue;
        }
        var opt = document.createElement("option");
        opt.setAttribute("value", brsrc_index[i].id());
        opt.appendChild(document.createTextNode(brsrc_index[i].barcode()));
        target_selector.appendChild(opt);
    }

    selector_memory.restore();
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

        reveal_dom_element(document.getElementById("reserve_under"));
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
                    visibleRange: "T01:30:00",
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
    if (bresv_dojo_items && bresv_dojo_items.length > 0) {
        cancel_reservations(
            bresv_dojo_items.map(function(o) { return bresv_index[o.id]; })
        );
    } else {
        alert(localeStrings.CXL_BRESV_SELECT_SOMETHING);
    }
}

/* Quick and dirty way to localize some strings; not recommended for reuse.
 * I'm sure dojo provides a better mechanism for this, but at the moment
 * this is faster to implement anew than figuring out the Right way to do
 * the same thing w/ dojo.
 */
function init_auto_l10n(el) {
    function do_it(myel, cls) {
        if (cls) {
            var clss = cls.split(" ");
            for (var k in clss) {
                var parts = clss[k].match(/^AUTO_ATTR_([A-Z]+)_.+$/);
                if (parts && localeStrings[clss[k]]) {
                    myel.setAttribute(
                        parts[1].toLowerCase(), localeStrings[clss[k]]
                    );
                } else if (clss[k].match(/^AUTO_/) && localeStrings[clss[k]]) {
                    myel.innerHTML = localeStrings[clss[k]];
                }
            }
        }
    }

    for (var i in el.attributes) {
        if (el.attributes[i].nodeName == "class") {
            do_it(el, el.attributes[i].value);
            break;
        }
    }
    for (var i in el.childNodes) {
        if (el.childNodes[i].nodeType == 1) { // element node?
            init_auto_l10n(el.childNodes[i]); // recurse!
        }
    }
}

/*
 * my_init
 */
function my_init() {
    hide_dom_element(document.getElementById("brt_reserve_block"));
    reveal_dom_element(document.getElementById("brt_search_block"));
    hide_dom_element(document.getElementById("reserve_under"));
    provide_brt_selector(document.getElementById("brt_selector_here"));
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));
    init_timestamp_widgets();
}

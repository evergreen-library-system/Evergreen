/* This module depends on common.js being loaded, as well as the
 * localization (Dojo/nls) for pickup and return . */

dojo.require("dojo.data.ItemFileReadStore");
dojo.require("dojo.date.locale");
dojo.require("openils.PermaCrud");
dojo.require("dojo.string");

function Populator(widgets, primary_input) {
    this.widgets = widgets;

    this.all = [];
    for (var k in widgets) this.all.push(k);

    if (primary_input) this.primary_input = primary_input;

    this.prepare_cache();
    this.prepare_empty_stores();
    this.reset();
}
Populator.prototype.prepare_cache = function(data) {
    this.cache = {};
    for (var k in this.all) this.cache[this.all[k]] = {};
};
Populator.prototype.prepare_empty_stores = function(data) {
    this.empty_stores = {};

    for (var i in this.all) {
        var name = this.all[i];

        if (this.widgets[name] && this["flatten_" + name]) {
            this.empty_stores[name] =
                new dojo.data.ItemFileReadStore({
                    "data": this["flatten_" + name]([])
                });
            this.widgets[name].setStore(this.empty_stores[name]);
        }
    }
};
Populator.prototype.flatten_ready = function(data) {
    return {
        "label": "id",
        "identifier": "id",
        "items": data.map(function(o) {
            return {
                "id": o.id(),
                "type": o.target_resource_type().name(),
                "resource": o.current_resource().barcode(),
                "start_time": humanize_timestamp_string(o.start_time()),
                "end_time": humanize_timestamp_string(o.end_time())
            };
        })
    };
};
Populator.prototype.flatten_out = function(data) {
    return {
        "label": "id",
        "identifier": "id",
        "items": data.map(function(o) {
            return {
                "id": o.id(),
                "type": o.target_resource_type().name(),
                "resource": o.current_resource().barcode(),
                "pickup_time": humanize_timestamp_string(o.pickup_time()),
                "end_time": humanize_timestamp_string(o.end_time())
            };
        })
    };
};
Populator.prototype.flatten_in = function(data) {
    return {
        "label": "id",
        "identifier": "id",
        "items": data.map(function(o) {
            return {
                "id": o.id(),
                "type": o.target_resource_type().name(),
                "resource": o.current_resource().barcode(),
                "due_time": humanize_timestamp_string(o.end_time()),
                "return_time": humanize_timestamp_string(o.return_time())
            };
        })
    };
};
Populator.prototype.reveal_container = function(widget) {
    var el = document.getElementById("contains_" + widget.id);
    if (el) reveal_dom_element(el);
};
Populator.prototype.hide_container = function(widget) {
    var el = document.getElementById("contains_" + widget.id);
    if (el) hide_dom_element(el);
};
Populator.prototype.populate_ready = function(data) {
    return this._populate_any_resv_grid(data, "ready");
};
Populator.prototype.populate_out = function(data) {
    return this._populate_any_resv_grid(data, "out");
};
Populator.prototype.populate_in = function(data) {
    return this._populate_any_resv_grid(data, "in");
};
Populator.prototype._populate_any_resv_grid = function(data, which) {
    var flattener = this["flatten_" + which];
    var widget = this.widgets[which];
    var cache = this.cache[which];
    var empty_store = this.empty_stores[which];

    this.reveal_container(widget);

    if (!data || !data.length) {
        widget.setStore(empty_store);
        this.toggle_anyness(false, which);
    } else {
        for (var i in data) cache[data[i].id()] = data[i];

        widget.setStore(
            new dojo.data.ItemFileReadStore({"data": flattener(data)})
        );

        this.toggle_anyness(true, which);

        /* Arrrgh! Horrid but necessary: */
        setTimeout(function() { widget.sort(); }, 100);
    }
};
Populator.prototype.populate_patron = function(data) {
    var h2 = document.createElement("h2");
    h2.setAttribute("class", "booking");
    h2.appendChild(document.createTextNode(formal_name(data)));

    this.widgets.patron.innerHTML = "";
    this.widgets.patron.appendChild(h2);

    this.reveal_container(this.widgets.patron);
    /* Maybe add patron's home OU or something here later... */
};
Populator.prototype.return_by_resource = function(barcode, override) {
    /* XXX instead of talking to the server every time we do this, we could
     * also check the "out" cache, iff we have one.  */
    var r = fieldmapper.standardRequest(
        ["open-ils.booking",
        "open-ils.booking.reservations.by_returnable_resource_barcode"],
        [openils.User.authtoken, barcode]
    );
    if (!r || r.length < 1) {
        alert(localeStrings.NO_SUCH_RETURNABLE_RESOURCE);
    } else if (is_ils_event(r)) {
        alert(my_ils_error(localeStrings.RETURNABLE_RESOURCE_ERROR, r));
    } else {
        try {
            var new_barcode = r.usr().card().barcode();
        } catch (E) {
            alert(localeStrings.RETURN_ERROR + "\nr: " + js2JSON(r) + "\n" + E);
            return;
        }
        if (this.patron_barcode && this.patron_barcode != new_barcode) {
            /* XXX make this more subtle, i.e. flash something in background */
            alert(localeStrings.NOTICE_CHANGE_OF_PATRON);
        }
        this.patron_barcode = new_barcode;
        var ret = this.return(r, override);
        if (!ret) {
            alert(localeStrings.RETURN_NO_RESPONSE);
        } else if (is_ils_event(ret) && ret.textcode != "SUCCESS") {
            if (ret.textcode == "ROUTE_ITEM") {
                display_transit_slip(ret);
            } else if (ret.textcode == "COPY_ALERT_MESSAGE") {
                if (
                    confirm(
                        dojo.string.substitute(
                            localeStrings.COPY_ALERT, [ret.desc, ret.payload]
                       )
                    )
                ) {
                    this.return_by_resource(barcode, true /*override*/);
                    return;
                }
            } else {
                alert(my_ils_error(localeStrings.RETURN_ERROR, ret));
            }
        } else {
            /* XXX speedbump should go, but something has to happen else
             * there's no indication to staff that anything happened when
             * starting from a fresh (blank) return interface.
             */
            alert(localeStrings.RETURN_SUCCESS);
        }
        this.populate(); /* Won't recurse with no args. All is well. */
    }
};
Populator.prototype.populate = function(barcode, which) {
    if (barcode) {
        if (barcode.patron) {
            this.patron_barcode = barcode.patron;
        }
        else if (barcode.resource) { /* resource OR patron, not both */
            if (!this.return_by_resource(barcode.resource))
                return;
        }
    }
    if (!this.patron_barcode) {
        alert(localeStrings.NO_PATRON_BARCODE);
        return;
    }

    if (!which) which = this.all;

    var result = fieldmapper.standardRequest(
        ["open-ils.booking", "open-ils.booking.reservations.get_captured"],
        [openils.User.authtoken, this.patron_barcode, which]
    );

    if (!result) {
        this.patron_barcode = undefined;
        alert(localeStrings.RESERVATIONS_NO_RESPONSE);
    } else if (is_ils_event(result)) {
        this.patron_barcode = undefined;
        alert(my_ils_error(localeStrings.RESERVATIONS_ERROR, result));
    } else {
        for (var k in result)
            this["populate_" + k](result[k]);
    }
};
Populator.prototype.toggle_anyness = function(any, which) {
    var widget = this.widgets[which].domNode;
    var empty_alternate = document.getElementById("no_" + widget.id);
    var controls = document.getElementById("controls_" + widget.id);
    if (any) {
        reveal_dom_element(widget);
        if (empty_alternate) hide_dom_element(empty_alternate);
        if (controls) reveal_dom_element(controls);
    } else {
        hide_dom_element(widget);
        if (empty_alternate) reveal_dom_element(empty_alternate);
        if (controls) hide_dom_element(controls);
    }
};
Populator.prototype.pickup = function(reservation) {
    return fieldmapper.standardRequest(
        ["open-ils.circ", "open-ils.circ.reservation.pickup"],
        [openils.User.authtoken, {
            "patron_barcode": this.patron_barcode,
            "reservation": reservation
        }]
    );
};
Populator.prototype.return = function(reservation, override) {
    var method = "open-ils.circ.reservation.return";
    if (override) method += ".override";
    return fieldmapper.standardRequest(
        ["open-ils.circ", method],
        [openils.User.authtoken, {
            "patron_barcode": this.patron_barcode,
            "reservation": reservation.id()
            /* yeah just id here ------^; lack of parallelism */
        }]
    );
};
Populator.prototype.act_on_selected = function(how, which) {
    var widget = this.widgets[which];
    var cache = this.cache[which];
    var no_response_msg = localeStrings[how.toUpperCase() + "_NO_RESPONSE"];
    var error_msg = localeStrings[how.toUpperCase() + "_ERROR"];

    var selected_id_list =
        widget.selection.getSelected().map(function(o) { return o.id[0]; });

    if (!selected_id_list || !selected_id_list.length) {
        alert(localeStrings.SELECT_SOMETHING);
        return;
    }

    var reservations = selected_id_list.map(function(o) { return cache[o]; });

    /* Do we have to process these one at a time?  I think so... */
    var self = this;
    function looper(reservation, override) {
        if (looper._done) return;
        var result = self[how](reservation, override);
        if (!result) {
            alert(no_response_msg);
        } else if (is_ils_event(result) && result.textcode != "SUCCESS") {
            if (result.textcode == "ROUTE_ITEM") {
                display_transit_slip(result);
            } else if (result.textcode == "COPY_ALERT_MESSAGE") {
                if (confirm(
                    dojo.string.substitute(
                        localeStrings.COPY_ALERT, [result.desc, result.payload]
                   )
                )) {
                    looper(reservation, true);
                }
                return; // continues processing other resvs
            } else {
                alert(my_ils_error(error_msg, result));
            }
        } else {
            return;
        }
        looper._done = true;
    }
    dojo.forEach(reservations, looper);

    this.populate();
};
Populator.prototype.reset = function() {
    for (var k in this.widgets) {
        this.hide_container(this.widgets[k]);
    }
    this.patron_barcode = undefined;

    if (typeof(this._extra_resetting) == "function")
        this._extra_resetting();

    if (this.primary_input) {
        this.primary_input.value = "";
        this.primary_input.focus();
    }
};

/* XXX needs to be combined with the code that shows transit slips in the
 * booking capture interface. */
function display_transit_slip(e) {
    var ou = fieldmapper.aou.findOrgUnit(e.org, /* slim_ok */false);
    var ma = (new openils.PermaCrud()).retrieve("aoa", ou.mailing_address());
    var mas = ma ?
        dojo.string.substitute(
            localeStrings.ADDRESS,
            [ma.street1(),ma.street2(),ma.city(),ma.state(),ma.post_code()].map(
                function(o) { return o ? o : ""; }
            )
        ).replace("\n\n", "\n").replace("\n", "<br />") : "[Unknown address]";
    /* XXX i18n and/or template */
    try {
        var win = window.open(
            "","","resizeable,width=600,height=400,scrollbars=1,chrome"
        );
        win.document.body.innerHTML =
            "<h1>Transit Slip</h1>\n" +
            //"<img src='/xul/server/skin/media/images/turtle.gif' />\n" +
            "<p>Destination: <strong>" + ou.name() + "</strong></p>\n" +
            "<p>" + mas + "</p>\n" +
            "<p>Barcode: " + e.payload.copy.barcode() + "<br />\n" +
            "Title: <span id='title'></span><br />\n" +
            "Author: <span id='author'></span><br />\n" +
            "Slip Date: " +
                dojo.date.locale.format(new Date(), {"formatLength": "short"}) +
            "</p>";
        fieldmapper.standardRequest(
            ["open-ils.search", "open-ils.search.biblio.mods_from_copy"], {
                "params": [e.payload.copy.id()],
                "async": true,
                "onresponse": function(r) {
                    var mvr = openils.Util.readResponse(r);
                    dojo.byId("title", win.document).innerHTML = mvr.title();
                    dojo.byId("author", win.document).innerHTML = mvr.author();
                },
                "oncomplete": function() {
                    win[confirm("Print transit slip?") ? "print" : "close"]();
                }
            }
        );
    } catch (E) {
        alert("exception rendering transit slip: " + E); // XXX
    }
}

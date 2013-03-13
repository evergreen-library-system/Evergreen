dojo.require("dijit.form.Button");
dojo.require("dijit.form.DateTextBox");
dojo.require("dijit.form.TextBox");
dojo.require("dijit.form.NumberSpinner");
dojo.require("dijit.form.FilteringSelect");
dojo.require("openils.widget.PCrudAutocompleteBox");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.ProgressDialog");
dojo.require("openils.PermaCrud");
dojo.require("openils.CGI");

var pcrud, cgi, issuance_id;
var sitem_cache = {};
var context_url_param;

function load_sitem_grid() {
    sitem_grid.overrideEditWidgets.status = status_selector;
    sitem_grid.overrideEditWidgets.status.shove = {};   /* sic */

    sitem_grid.dataLoader = sitem_data_loader;
    sitem_grid.dataLoader();
}

function load_siss_display() {
    pcrud.retrieve(
        "siss", issuance_id, {
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    var link = dojo.byId("siss_label_here");
                    link.onclick = function() {
                        location.href = oilsBasePath +
                            "/serial/subscription?id=" +
                            r.subscription() + "&tab=issuances" +
                            context_url_param;
                    }
                    link.innerHTML = r.label();
                    prepare_create_dialog(r.subscription());
                }
            }
        }
    );
}

function sitem_data_loader() {
    sitem_grid.resetStore();
    sitem_grid.showLoadProgressIndicator();

    fieldmapper.standardRequest(
        ["open-ils.serial", "open-ils.serial.items.by_issuance"], {
            "params": [
                openils.User.authtoken, issuance_id, {
                    "limit": sitem_grid.displayLimit,
                    "offset": sitem_grid.displayOffset
                }
            ],
            "async": true,
            "onresponse": function(r) {
                var item = openils.Util.readResponse(r);
                sitem_cache[item.id()] = item;
                sitem_grid.store.newItem(item.toStoreItem());
            },
            "oncomplete": function(r) {
                sitem_grid.hideLoadProgressIndicator();
            }
        }
    );
}

function _get_field(store, item, field) {
    if (!item) return "";
    var id = store.getValue(item, "id");
    return sitem_cache[id][field]();
}

/* create the get_foo() functions used by our AutoGrid */
["creator", "editor", "stream", "unit"].forEach(
    function(field) {
        window["get_" + field] = function(row_index, item) {
            return _get_field(this.grid.store, item, field);
        };
    }
);

function format_user(user) {
    return user ? user.usrname() : "";
}

function format_stream(stream) {
    return stream ? (stream.routing_label() || "[None]") : ""; /* XXX i18n */
}

function format_unit(unit) {
    return unit ? (unit.barcode() || "[None]") : ""; /* XXX i18n */
}

function update_sitem_safely(obj, opts, edit_pane) {
    fieldmapper.standardRequest(
        ["open-ils.serial", "open-ils.serial.item.update"], {
            "params": [openils.User.authtoken, obj],
            "async": true,
            "oncomplete": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (edit_pane.onPostSubmit)
                        edit_pane.onPostSubmit(null, [r]);
                }
            }
        }
    );
}

function prepare_create_dialog(sub_id) {
    pcrud.search(
        "sdist", {"subscription": sub_id}, {
            "id_list": true,
            "async": true,
            "oncomplete": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    new openils.widget.PCrudAutocompleteBox({
                        "fmclass": "sstr",
                        "searchAttr": "routing_label",
                        "hasDownArrow": true,
                        "name": "stream",
                        "store_options": {
                            "base_filter": {"distribution": r},
                            "honor_retrieve_all": true
                        }
                    }, "stream_selector");
                }
            }
        }
    );
}

function create_new_items(form) {
    var item = new sitem();
 
    item.issuance(issuance_id);    /* from global */
    item.stream(form.stream);
    item.status(form.status);
    item.date_expected(
        form.date_expected ?
            dojo.date.stamp.toISOString(form.date_expected) : null
    );
    item.date_received(
        form.date_received ?
            dojo.date.stamp.toISOString(form.date_received) : null
    );

    progress_dialog.show(true);
    fieldmapper.standardRequest(
        ["open-ils.serial", "open-ils.serial.item.create"], {
            "params": [openils.User.authtoken, item, form.count],
            "async": true,
            "oncomplete": function(r) {
                progress_dialog.hide();
                if (r = openils.Util.readResponse(r)) {
                    sitem_grid.refresh();
                }
            }
        }
    );
}

openils.Util.addOnLoad(
    function() {
        cgi = new openils.CGI();
        pcrud = new openils.PermaCrud();

        issuance_id = cgi.param("issuance");
        load_siss_display();
        load_sitem_grid();

        var context = cgi.param('context');
        if (context) {
            context_url_param = '&context=' + context;
        } else {
            context_url_param = '';
        }
    }
);

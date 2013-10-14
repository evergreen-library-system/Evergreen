dojo.require("dijit.form.Button");
dojo.require("dijit.form.RadioButton");
dojo.require("dijit.form.FilteringSelect");
dojo.require("dijit.form.DropDownButton");
dojo.require("dijit.TooltipDialog");
dojo.require("dijit.layout.TabContainer");
dojo.require("dijit.layout.ContentPane");
dojo.require("dojox.grid.DataGrid");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.ProgressDialog");
dojo.require("openils.widget.HoldingCode");
dojo.require("openils.PermaCrud");
dojo.require("openils.CGI");
dojo.requireLocalization('openils.serial', 'serial');
var localeStrings = dojo.i18n.getLocalization('openils.serial', 'serial');

var pcrud;
var cgi;
var sub;
var sub_id;
var context_url_param;

function node_by_name(name, ctx) {
    return dojo.query("[name='" + name + "']", ctx)[0];
}

/* typing save: add {get,set}Value() to all HTML <select> elements */
HTMLSelectElement.prototype.getValue = function() {
    return this.options[this.selectedIndex].value;
}
HTMLSelectElement.prototype.setValue = function(s) {
    for (var i = 0; i < this.options.length; i++) {
        if (s == this.options[i].value) {
            this.selectedIndex = i;
            break;
        }
    }
}

function load_sub_grid(id, oncomplete) {
    if (!pcrud) return; /* first run, onLoad hasn't fired yet */
    if (!sub_grid._fresh) {
        var dist_ids = pcrud.search(
            "sdist", {"subscription": id}, {"id_list": true}
        );
        pcrud.retrieve(
            "ssub", id, {
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        sub = r;
                        var data = ssub.toStoreData([r]);
                        data.items[0].num_dist = dist_ids ? dist_ids.length : 0;
                        sub_grid.setStore(
                            new dojo.data.ItemFileReadStore({"data": data})
                        );
                        sub_grid._fresh = true;
                    }
                },
                "oncomplete": function() {
                    if (oncomplete) oncomplete();
                }
            }
        );
    }
}

/* TODO: make these formatters caching */
function format_bib(bib_id) {
    if (!bib_id) {
        return "";
    } else {
        var result;
        fieldmapper.standardRequest(
            ["open-ils.search",
                "open-ils.search.biblio.record.mods_slim.retrieve"], {
                "async": false,
                "params": [bib_id],
                "oncomplete": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        var parts = [];
                        if (r.title())
                            parts.push(r.title());
                        if (r.author())
                            parts.push(r.author());
                        if (r.author())
                            parts.push(r.publisher());

                        if (!parts.length)
                            parts.push(r.tcn());

                        result = parts.join(" / ");
                    }
                }
            }
        );
        return "<a href='" + oilsBasePath +
            "/serial/list_subscription?record_entry=" + bib_id + "'>" +
            result + "</a>";
    }
}

function format_date(s) {
    return s ? openils.Util.timeStamp(s, {"selector": "date"}) : "";
}

function format_org_unit(aou_id) {
    return aou_id ? aou.findOrgUnit(aou_id).shortname() : "";
}

function get_id_and_label(rowIndex, item) {
    if (!item) return {"id": "", "label": ""};
    return {
        "id": this.grid.store.getValue(item, "id"),
        "label": this.grid.store.getValue(item, "label")
    };
}

function format_siss_label(blob) {
    if (!blob.id) return "";
    return "<a href='" +
        oilsBasePath + "/serial/list_item?issuance=" + blob.id +
        context_url_param + "'>" + (blob.label ? blob.label : "[None]") +
        "</a>"; /* XXX i18n */
}

function format_sdist_label(blob) {
    if (!blob.id) return "";
    var link = "<a href='" +
        oilsBasePath + "/serial/list_stream?distribution=" + blob.id +
        context_url_param + "'>" + (blob.label ? blob.label : "[None]") +
        "</a>"; /* XXX i18n */

    var sstr_list = pcrud.search(
        "sstr",{"distribution":blob.id},{"id_list":true}
    );
    count = sstr_list ? sstr_list.length : 0;
    link += "&nbsp;&nbsp; " + count + " stream(s)"; //XXX i18n
    return link;
}

function append_stream_count(dist_id) {
    var span = dojo.byId("dist_link_" + dist_id);
    if (span.childNodes.length) /* textNodes count as childnodes */
        return;
    pcrud.search(
        "sstr", {"distribution": dist_id}, {
            "id_list": true,
            "oncomplete": function(r) {
                var resp = openils.Util.readResponse(r);
                var count = resp ? resp.length : 0;

                /* XXX i18n */
                span.innerHTML = "&nbsp;&nbsp; " + count + " stream(s)";
            }
        }
    );
}

function open_batch_receive() {
    if (!sub) {
        alert("Let the interface load all the way first.");
        return;
    }

    var url = "XUL_SERIAL_BATCH_RECEIVE?docid=" +
        sub.record_entry() + "&subid=" + sub.id();

    try {
        openils.XUL.newTabEasy(url, "Batch Receive"); /* XXX i18n */
    } catch (E) {
        location.href = url;
    }
}

function toggle_clone_ident_field(dij) {
    setTimeout(
        function() {
            var disabled = !dij.attr("checked");
            clone_ident.attr("disabled", disabled);
            if (!disabled) clone_ident.focus();
        }, 175
    );
}

function clone_subscription(form) {
    if (form.use_ident == "yes") {
        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.biblio.record_entry.by_identifier.atomic"], {
                "params": [form.ident, {"id_list": true}],
                "async": true,
                "oncomplete": function(r) {
                    r = openils.Util.readResponse(r);
                    if (!r || !r.length) {
                        alert("No matches for that indentifier."); /*XXX i18n*/
                    } else if (r.length != 1) {
                        alert("Too many matches for that identifier. Use a " +
                            "unique identifier."); /* XXX i18n */
                    } else {
                        _clone_subscription(r[0]);
                    }
                }
            }
        );
    } else {
        _clone_subscription();
    }
}

function _clone_subscription(bre_id) {
    progress_dialog.show(true);

    fieldmapper.standardRequest(
        ["open-ils.serial", "open-ils.serial.subscription.clone"], {
            "params": [openils.User.authtoken, sub_id, bre_id],
            "async": false,
            "oncomplete": function(r) {
                progress_dialog.hide();
                if (!(r = openils.Util.readResponse(r))) {
                    alert("Error cloning subscription."); /* XXX i18n */
                } else {
                    location.href =
                        oilsBasePath + "/serial/subscription?id=" + r;
                }

                /* cloning doesn't clone holdings, so nothing changes at
                 * OPAC view just because of this, so no need to try
                 * reload_opac().  */
            }
        }
    );
}

function open_notes(obj_type, grid) {
    if (grid.getSelectedRows().length != 1) {
        alert( localeStrings.REQUIRE_ONE_ROW );
        return;
    }

    var id = grid.getSelectedItems()[0].id[0];
    var args_by_obj_type = {
        'sub' : { 'function_type' : 'SSUBN', 'object_type' : 'subscription', 'constructor' : ssubn, 'title' : dojo.string.substitute(localeStrings.NOTES_SSUB, [id]) },
        'dist' : { 'function_type' : 'SDISTN', 'object_type' : 'distribution', 'constructor' : sdistn, 'title' : dojo.string.substitute(localeStrings.NOTES_SDIST, [id]) }
    };
    args_by_obj_type[obj_type].object_id = id;

    try {
        window.openDialog(
            xulG.url_prefix('XUL_SERIAL_NOTES'),
            obj_type+'_notes',
            'chrome,resizable,modal',
            args_by_obj_type[obj_type]
        );
    } catch (E) {
        alert(E); /* XXX */
    }
}

openils.Util.addOnLoad(
    function() {
        var tab_dispatch = {
            "distributions": distributions_tab,
            "issuances": issuances_tab
        };

        cgi = new openils.CGI();
        pcrud = new openils.PermaCrud();

        context = cgi.param("context");
        sub_id = cgi.param("id");
        owning_lib = cgi.param("owning_lib");
        record_entry = cgi.param("record_entry");

        if (context) {
            context_url_param = '&context=' + context;
        } else {
            context_url_param = '';
        }

        if (context != 'scv') {
            load_sub_grid(
                sub_id,
                (cgi.param("tab") in tab_dispatch) ?
                    function() {
                        tab_container.selectChild(
                            tab_dispatch[cgi.param("tab")]
                        );
                    } : null
            );
        } else {
            build_sre_maps(dist_grid);
            dist_grid.empty_store = new dojo.data.ItemFileReadStore({
                "data": {
                    "identifier": "record_entry",
                    "label": "label",
                    "items": []
                }
            })
            dist_grid.overrideEditWidgets.record_entry =
                new dijit.form.FilteringSelect({
                    "store" : dist_grid.empty_store,
                    "searchAttr" : "label",
                    "name" : "record_entry"
                });
            dist_grid.overrideEditWidgets.record_entry.shove = {};
            dist_grid.onPostCreate = function() { this.refresh(); };
            dist_grid.createPaneOnSubmit = function(fmObject, opts, pane) {
                fmObject.isnew(1);
                fieldmapper.standardRequest(
                    ['open-ils.serial', 'open-ils.serial.distribution.fleshed.batch.update'],
                    {
                        "async":false,
                        "params":[openils.User.authtoken, [fmObject]],
                        "oncomplete": function(r) {
                            // TODO: adjust create method to send back fmObject,
                            // then pass through to avoid need for onPostCreate
                            // refresh
                            // TODO: check for and handle possible errors
                            pane.onPostSubmit(null, []);
                        }
                    }
                );
            };
            if (sub_id == 'new') {
                ssub_grid.overrideEditWidgets.record_entry =
                        new dijit.form.TextBox({
                            "disabled": true, "value": record_entry
                        });
                ssub_grid.overrideWidgetArgs.owning_lib = {widgetValue : owning_lib, dijitArgs : {disabled : true}};

                ssub_grid.onPostCreate = function(fmObject) {
                    sub_id = fmObject.id();
                    parent.document.getElementById(window.name).refresh_command(fmObject);
                }

                ssub_grid.showCreateDialog();
            } else {
                ssub_grid.overrideWidgetArgs.record_entry = {widgetClass : "dijit.form.TextBox", dijitArgs : {disabled : true}};
            }
            ssub_grid.onPostUpdate = function(fmObject) {
                parent.document.getElementById(window.name).refresh_command();
            }
            ssub_grid.onItemReceived = function(item) {
                sub = item;
            }
            if (cgi.param("tab") in tab_dispatch) {
                ssub_grid._fresh = false; // force View/Edit tab to reload (otherwise, it is blank) XXX why?
                tab_container.selectChild(tab_dispatch[cgi.param("tab")]);
            }
            parent.document.getElementById(window.name).style.visibility = 'visible'; // unhide the editor pane (iframe)
        }
    }
);

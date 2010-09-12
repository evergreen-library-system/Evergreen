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
dojo.require("openils.PermaCrud");

var pcrud;
var sub;

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

function load_sub_grid(id) {
    if (!pcrud) return; /* first run, onLoad hasn't fired yet */
    if (!sub_grid._fresh) {
        pcrud.retrieve(
            "ssub", id, {
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        sub = r;
                        sub_grid.setStore(
                            new dojo.data.ItemFileReadStore(
                                {"data": ssub.toStoreData([r])}
                            )
                        );
                        sub_grid._fresh = true;
                    }
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
        return "<a href='" + oilsBasePath + "/serial/list_subscription/" +
            bib_id + "'>" + result + "</a>";
    }
}

function format_date(s) {
    return s ? openils.Util.timeStamp(s, {"selector": "date"}) : "";
}

function format_org_unit(aou_id) {
    return aou_id ? aou.findOrgUnit(aou_id).shortname() : "";
}

function get_sdist(rowIndex, item) {
    if (!item) return {"id": "", "label": ""};
    return {
        "id": this.grid.store.getValue(item, "id"),
        "label": this.grid.store.getValue(item, "label")
    };
}

function format_sdist_label(blob) {
    if (!blob.id) return "";
    var link = "<a href='" +
        oilsBasePath + "/serial/list_stream/" + blob.id +
        "'>" + (blob.label ? blob.label : "[None]") + "</a>" + /* XXX i18n */
        "<span id='dist_link_" + blob.id + "'></span>";

    /* XXX kludgy kludge kludge */
    setTimeout(function() { append_stream_count(blob.id); }, 200);

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

    var url = "/xul/server/serial/batch_receive.xul?docid=" +
        sub.record_entry() + "&subid=" + sub.id();

    try {
        openils.XUL.newTabEasy(url, "Batch Receive"); /* XXX i18n */
    } catch (E) {
        location.href = url;
    }
}

openils.Util.addOnLoad(
    function() {
        pcrud = new openils.PermaCrud();
        load_sub_grid(sub_id);
    }
);

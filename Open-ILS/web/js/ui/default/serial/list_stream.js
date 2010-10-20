dojo.require("dijit.form.Button");
dojo.require("dijit.form.NumberSpinner");
dojo.require("dijit.form.TextBox");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.ProgressDialog");
dojo.require("openils.PermaCrud");
dojo.require("openils.CGI");

var pcrud;
var dist_id;
var cgi;

function format_routing_label(routing_label) {
    return routing_label ? routing_label : "[None]";
}

function load_sstr_grid() {
    sstr_grid.overrideEditWidgets.distribution =
        new dijit.form.TextBox({"disabled": true, "value": dist_id});

    sstr_grid.resetStore();
    sstr_grid.loadAll(
        {"order_by": {"ssub": "start_date DESC"}},
        {"distribution": dist_id}
    );
}

function load_sdist_display() {
    pcrud.retrieve(
        "sdist", dist_id, {
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    var link = dojo.byId("sdist_label_here");
                    link.onclick = function() {
                        location.href = oilsBasePath +
                            "/eg/serial/subscription?id=" +
                            r.subscription() + "&tab=distributions";
                    }
                    link.innerHTML = r.label();
                    load_sdist_org_unit_display(r);
                }
            }
        }
    );
}

function load_sdist_org_unit_display(dist) {
    dojo.byId("sdist_org_unit_name_here").innerHTML =
        aou.findOrgUnit(dist.holding_lib()).name();
}

function create_many_streams(fields) {
    var streams = [];
    for (var i = 0; i < fields.quantity; i++) {
        var stream = new sstr();
        stream.distribution(dist_id);
        streams.push(stream);
    }

    progress_dialog.show(true);
    this.pcrud.create(
        streams, {
            "oncomplete": function(r, list) {
                progress_dialog.hide();
                sstr_grid.refresh();
            },
            "onerror": function(r) {
                progress_dialog.hide();
                alert("Error creating streams!"); /* XXX i18n */
            }
        }
    );
}

openils.Util.addOnLoad(
    function() {
        cgi = new openils.CGI();
        pcrud = new openils.PermaCrud();

        dist_id = cgi.param("distribution");
        load_sdist_display();
        load_sstr_grid();
    }
);

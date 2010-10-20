dojo.require("dijit.form.Button");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.require("openils.BibTemplate");
dojo.require("openils.CGI");

var terms;
var cgi;

function format_ssub_link(id) {
    return "<a href='" + oilsBasePath + "/serial/subscription?id=" +
        id + "'>" + id + "</a>";
}

function load_ssub_grid() {
    ssub_grid.resetStore();
    ssub_grid.loadAll({"order_by": {"ssub": "start_date DESC"}}, terms);
}

openils.Util.addOnLoad(
    function() {
        cgi = new openils.CGI();

        terms = {
            "owning_lib": aou.orgNodeTrail(
                aou.findOrgUnit(openils.User.user.ws_ou()),
                true /* asId */
            ),
            "record_entry": cgi.param("record_entry") || _fallback_record_entry
        };

        if (terms.record_entry)
            new openils.BibTemplate({"record": terms.record_entry}).render();

        /* This should be present even if terms.record_entry is undef */
        ssub_grid.overrideEditWidgets.record_entry = new dijit.form.TextBox(
            {"value": terms.record_entry, "disabled": true}
        );

        new openils.User().buildPermOrgSelector(
            "ADMIN_SERIAL_SUBSCRIPTION",
            ssub_owner_select,
            null,
            function() {
                dojo.connect(
                    ssub_owner_select,
                    "onChange",
                    function() {
                        terms.owning_lib = aou.orgNodeTrail(
                            aou.findOrgUnit(this.attr("value")),
                            true /* asId */
                        );
                        load_ssub_grid();
                    }
                );
                load_ssub_grid();
            }
        );
    }
);

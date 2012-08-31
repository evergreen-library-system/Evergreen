if (!dojo._hasResource["openils.URLVerify.ReviewAttempt"]) {
    dojo.require("dojo.string");
    dojo.require("openils.CGI");
    dojo.require("openils.PermaCrud");
    dojo.require("dijit.Tooltip");

    dojo.requireLocalization("openils.URLVerify", "URLVerify");

    dojo._hasResource["openils.URLVerify.ReviewAttempt"] = true;
    dojo.provide("openils.URLVerify.ReviewAttempt");

    dojo.declare("openils.URLVerify.ReviewAttempt", null, {});

    /* Take care that we add nothing to the global namespace.
     * This is not an OO module so much as a container for
     * functions needed by a specific interface. */

(function() {
    var module = openils.URLVerify.ReviewAttempt;
    var localeStrings =
        dojo.i18n.getLocalization("openils.URLVerify", "URLVerify");

    module._display_session_name = function() {
        var pcrud = new openils.PermaCrud();

        var attempt = pcrud.retrieve(
            "uvva", module.attempt_id, {
                "flesh": 1, "flesh_fields": {"uvva": ["session"]}
            }
        );

        dojo.byId("session-link-here").innerHTML =
            "<a href='select_urls?session_id=" + attempt.session().id() + "'>" +
            dojo.string.substitute(
                localeStrings.SESSION_NAME, [attempt.session().name()]
            ) + "</a>";

        pcrud.disconnect();

        new dijit.Tooltip({
            "connectId": "session-link-here",
            "label": localeStrings.SELECT_MORE
        });
    };

    module.setup = function(grid, progress_dialog) {
        module.progress_dialog = progress_dialog;
        module.progress_dialog.attr("title", localeStrings.INTERFACE_SETUP);
        module.progress_dialog.show(true);

        var cgi = new openils.CGI();
        module.attempt_id = cgi.param("attempt_id");

        module.grid = grid;

        module.grid.setBaseQuery({"attempt_id": module.attempt_id});

        module.grid.refresh();

        module._display_session_name();

        module.progress_dialog.hide();
    };

}());

}

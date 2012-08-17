if (!dojo._hasResource["openils.URLVerify.SelectURLs"]) {
    dojo.require("dojo.string");
    dojo.require("openils.CGI");
    dojo.require("openils.Util");

    dojo.requireLocalization("openils.URLVerify", "URLVerify");

    dojo._hasResource["openils.URLVerify.SelectURLs"] = true;
    dojo.provide("openils.URLVerify.SelectURLs");

    dojo.declare("openils.URLVerify.SelectURLs", null, {});

    /* Take care that we add nothing to the global namespace.
     * This is not an OO module so much as a container for
     * functions needed by a specific interface. */

(function() {
    var module = openils.URLVerify.SelectURLs;
    var localeStrings =
        dojo.i18n.getLocalization("openils.URLVerify", "URLVerify");

    module.setup = function(grid, progress_dialog) {
        var cgi = new openils.CGI();
        module.session_id = cgi.param("session_id");

        module.grid = grid;

        module.grid.attr("query", {"session_id": module.session_id});
        module.grid.refresh();
        // Alternative to grid.refresh() once filter is set up
        //module.grid.fetchLock = false;
        //module.grid.filterUi.doApply();
    };

    module.verify_selected = function() {
        var really_everything = false;

        if (module.grid.everythingSeemsSelected())
            really_everything = confirm(localeStrings.VERIFY_ALL);

        module.clear_attempt_display();
        progress_dialog.attr("title", localeStrings.VERIFICATION_BEGIN);
        progress_dialog.show();

        fieldmapper.standardRequest(
            ["open-ils.url_verify", "open-ils.url_verify.session.verify"], {
                "params": [
                    openils.User.authtoken,
                    module.session_id,
                    really_everything ? null : module.grid.getSelectedIDs()
                ],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        progress_dialog.attr(
                            "title",
                            dojo.string.substitute(
                                localeStrings.VERIFICATION_PROGRESS,
                                [r.total_processed]
                            )
                        );
                        progress_dialog.update({
                            "maximum": r.url_count,
                            "progress": r.total_excluding_redirects
                        });

                        if (r.attempt)
                            module.update_attempt_display(r.attempt);
                    }
                }
            }
        )

        module.grid.getSelectedIDs();   
    };

    module.clear_attempt_display = function() {
        dojo.empty(dojo.byId("url-verify-attempt-id"));
        dojo.empty(dojo.byId("url-verify-attempt-start"));
        dojo.empty(dojo.byId("url-verify-attempt-finish"));
    };

    module.update_attempt_display = function(attempt) {
        dojo.byId("url-verify-attempt-id").innerHTML =
            dojo.string.substitute(
                localeStrings.VERIFICATION_ATTEMPT_ID,
                [attempt.id()]
            );
        dojo.byId("url-verify-attempt-start").innerHTML =
            dojo.string.substitute(
                localeStrings.VERIFICATION_ATTEMPT_START,
                [attempt.start_time()]
            );

        if (attempt.finish_time()) {
            dojo.byId("url-verify-attempt-finish").innerHTML =
                dojo.string.substitute(
                    localeStrings.VERIFICATION_ATTEMPT_FINISH,
                    [attempt.finish_time()]
                );
        }
    };

}());

}

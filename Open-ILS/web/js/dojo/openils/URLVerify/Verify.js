if (!dojo._hasResource["openils.URLVerify.Verify"]) {

    dojo.requireLocalization("openils.URLVerify", "URLVerify");

    dojo._hasResource["openils.URLVerify.Verify"] = true;
    dojo.provide("openils.URLVerify.Verify");

    dojo.declare("openils.URLVerify.Verify", null, {});

    /* Take care that we add nothing to the global namespace.
     * This is not an OO module so much as a container for
     * functions needed by specific interfaces. */

(function() {
    var module = openils.URLVerify.Verify;
    var localeStrings =
        dojo.i18n.getLocalization("openils.URLVerify", "URLVerify");

    module.go = function(session_id, url_id_list, progress_dialog) {
        progress_dialog.attr("title", localeStrings.VERIFICATION_DIALOG);
        progress_dialog.show();

        fieldmapper.standardRequest(
            ["open-ils.url_verify", "open-ils.url_verify.session.verify"], {
                "params": [openils.User.authtoken, session_id, url_id_list],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        progress_dialog.update({
                            "maximum": r.url_count,
                            "progress": r.total_excluding_redirects
                        });

                        if (r.attempt) {
                            module.attempt = r.attempt;
                            progress_dialog.show(
                                false,
                                dojo.string.substitute(
                                    localeStrings.VERIFICATION_ATTEMPT_ID,
                                    [r.attempt.id()]
                                )
                            );
                        }
                    }
                },
                "oncomplete": function() {
                    progress_dialog.show(true);
                    progress_dialog.attr("title", localeStrings.REDIRECTING);
                    location.href = oilsBasePath +
                        "/url_verify/review_attempt?attempt_id=" +
                        module.attempt.id();
                }
            }
        );
    };

}());

}

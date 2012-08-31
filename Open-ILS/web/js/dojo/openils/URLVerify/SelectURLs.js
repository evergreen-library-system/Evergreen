if (!dojo._hasResource["openils.URLVerify.SelectURLs"]) {
    dojo.require("dojo.string");
    dojo.require("openils.CGI");
    dojo.require("openils.Util");
    dojo.require("openils.PermaCrud");
    dojo.require("openils.URLVerify.Verify");

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
        module.progress_dialog = progress_dialog;
        module.progress_dialog.attr("title", localeStrings.INTERFACE_SETUP);
        module.progress_dialog.show(true);

        var cgi = new openils.CGI();
        module.session_id = cgi.param("session_id");

        module.grid = grid;

        module.grid.setBaseQuery({"session_id": module.session_id});

        module.grid.refresh();
        // Alternative to grid.refresh() once filter is set up
        //module.grid.fetchLock = false;
        //module.grid.filterUi.doApply();

        module._display_session_name();

        module.progress_dialog.hide();
    };

    module._display_session_name = function() {
        var pcrud = new openils.PermaCrud();

        pcrud.retrieve(
            "uvs", module.session_id, {
                "async": true,
                "oncomplete": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        dojo.byId("session-name-here").innerHTML =
                            dojo.string.substitute(
                                localeStrings.SESSION_NAME, [r.name()]
                            );

                        pcrud.disconnect();
                    }
                }
            }
        );
    };

    module.verify_selected = function() {
        if (module.grid.getSelectedItems().length < 1) {
            alert(localeStrings.NOTHING_SELECTED);
            return;
        }

        if (module.grid.everythingSeemsSelected() &&
            confirm(localeStrings.VERIFY_ALL)) {
            /* If we're here, the user wants to verify all URLs matching
             * the grid's current filters. We need to reach down to the
             * grid's store to do a special fetch to get all those IDs. */

            module.grid.store.fetch({
                "query": dojo.clone(module.grid.query),
                "queryOptions": {"all": true},
                "onComplete": function(rows) {
                    openils.URLVerify.Verify.go(
                        module.session_id,
                        dojo.map(rows, function(row) { return row.id; }),
                        module.progress_dialog
                    );
                }
            });
        } else {
            /* If we're here, the user wants to verify just the rows he
             * specifically selected with the checkboxes. */
            openils.URLVerify.Verify.go(
                module.session_id,
                module.grid.getSelectedIDs(),
                module.progress_dialog
            );
        }
    };

}());

}

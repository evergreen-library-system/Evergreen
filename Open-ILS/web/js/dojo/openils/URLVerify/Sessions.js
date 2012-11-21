if (!dojo._hasResource["openils.URLVerify.Sessions"]) {
    dojo.require("dojo.string");
    dojo.require("openils.Util");
    dojo.require("openils.URLVerify.Verify");

    dojo.requireLocalization("openils.URLVerify", "URLVerify");

    dojo._hasResource["openils.URLVerify.Sessions"] = true;
    dojo.provide("openils.URLVerify.Sessions");

    dojo.declare("openils.URLVerify.Sessions", null, {});

    /* Take care that we add nothing to the global namespace.
     * This is not an OO module so much as a container for
     * functions needed by a specific interface. */

(function() {
    var module = openils.URLVerify.Sessions;
    var localeStrings =
        dojo.i18n.getLocalization("openils.URLVerify", "URLVerify");

    module.setup = function(grid, org_selector) {
        module.grid = grid;

        module.setup_org_selector_for_grid(org_selector);
    };

    module.setup_org_selector_for_grid = function(org_selector) {
        function filter_grid_by_selected_org() {
            module.grid.query = {
                "owning_lib": org_selector.attr("value")
            };
            module.grid.refresh();
        }

        new openils.User().buildPermOrgSelector(
            "URL_VERIFY", org_selector, null,
            function() {
                dojo.connect(
                    org_selector, "onChange", filter_grid_by_selected_org
                );
                filter_grid_by_selected_org();
            }
        );
    };

    module.format_id = function(str) {
        if (!str)
            return "";

        return str + " [<a href='select_urls?session_id=" + str + "' title='" +
            localeStrings.REREVIEW + "'>" + localeStrings.REREVIEW +
            "</a>] [<a href='create_session?clone=" + str + "' title='" +
            localeStrings.CLONE_SESSION + "'>" +
            localeStrings.CLONE_SESSION + "</a>]";
    };

    module.format_attempts = function(list) {
        if (!dojo.isArray(list)) return "";

        return dojo.map(
            list, function(id) {
                if (isNaN(id))
                    return "";
                return id + " [<a title='" + localeStrings.REVIEW_ATTEMPT +
                    "' href='review_attempt?attempt_id=" + id + "'>" +
                    localeStrings.REREVIEW + "</a>]";
            }
        ).join(" / ");
    };

}());

}

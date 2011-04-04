dojo.require("openils.User");
dojo.require("openils.PermaCrud");
dojo.require("fieldmapper.OrgUtils");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.requireLocalization("openils.booking", "pull_list");

var localeStrings = dojo.i18n.getLocalization("openils.booking", "pull_list");
var pcrud = new openils.PermaCrud();

var owning_lib_selected;
var acp_cache = {};

function init_owning_lib_selector() {
    var User = new openils.User();
    User.buildPermOrgSelector(
        "RETRIEVE_RESERVATION_PULL_LIST", owning_lib_selector, null,
        function() {
            owning_lib_selected = owning_lib_selector.getValue();
            dojo.connect(owning_lib_selector, "onChange",
                function() { owning_lib_selected = this.getValue(); }
            )
        }
    );
}

function retrieve_pull_list(ivl_in_days) {
    var secs = Number(ivl_in_days) * 86400;

    if (isNaN(secs) || secs < 1)
        throw new Error("Invalid interval");

    return fieldmapper.standardRequest(
        ["open-ils.booking", "open-ils.booking.reservations.get_pull_list"],
        [openils.User.authtoken, null, secs, owning_lib_selected]
    );
}

function dom_table_rowid(resource_id) {
    return "pull_list_resource_" + resource_id;
}

function generate_result_row(one) {
    function cell(id, content) {
        var td = document.createElement("td");
        if (id != undefined) td.setAttribute("id", id);
        td.appendChild(document.createTextNode(content));
        return td;
    }

    function render_pickup_lib(pickup_lib) {
        var span = document.createElement("span");
        if (pickup_lib != owning_lib_selected)
            span.setAttribute("class", "pull_list_will_transit");
        span.innerHTML = localeStrings.AT + " " +
            fieldmapper.aou.findOrgUnit(pickup_lib).shortname();
        return span;
    }

    function reservation_info_cell(one) {
        var td = document.createElement("td");
        for (var i in one.reservations) {
            var one_resv = one.reservations[i];
            var div = document.createElement("div");
            div.setAttribute("class", "pull_list_resv_detail");
            var content = [
                document.createTextNode(
                    humanize_timestamp_string(one_resv.start_time()) +
                    " - " + humanize_timestamp_string(one_resv.end_time())
                ),
                document.createElement("br"),
                render_pickup_lib(one_resv.pickup_lib()),
                document.createTextNode(
                    " " + localeStrings.FOR + " " + formal_name(one_resv.usr())
                )
            ];
            for (var k in content) { div.appendChild(content[k]); }
            td.appendChild(div);
        }
        return td;
    }

    var baseid = dom_table_rowid(one.current_resource.id());

    var cells = [];
    cells.push(cell(undefined, one.target_resource_type.name()));
    cells.push(cell(undefined, one.current_resource.barcode()));
    cells.push(cell(baseid + "_call_number", "-"));
    cells.push(cell(baseid + "_copy_location", "-"));
    cells.push(reservation_info_cell(one));

    var row = document.createElement("tr");
    row.setAttribute("id", baseid);

    for (var i in cells) row.appendChild(cells[i]);
    return row;
}

function render_pull_list_fundamentals(list) {
    var rows = [];

    for (var i in list)
        rows.push(generate_result_row(list[i]));

    document.getElementById("the_table_body").innerHTML = "";

    for (var i in rows)
        document.getElementById("the_table_body").appendChild(rows[i]);
}

function get_all_relevant_acp(list) {
    var barcodes = [];
    for (var i in list) {
        if (list[i].target_resource_type.catalog_item()) {
            /* There shouldn't be any duplicates. No need to worry bout that */
            barcodes.push(list[i].current_resource.barcode());
        }
    }
    if (barcodes.length > 0) {
        var results = fieldmapper.standardRequest(
            [
                "open-ils.booking",
                "open-ils.booking.asset.get_copy_fleshed_just_right"
            ],
            [openils.User.authtoken, barcodes]
        );

        if (!results) {
            alert(localeStrings.COPY_LOOKUP_NO_RESPONSE);
            return null;
        } else if (is_ils_event(results)) {
            alert(my_ils_error(localeStrings.COPY_LOOKUP_ERROR, results));
            return null;
        } else {
            return results;
        }
    }
    return null;
}

function fill_in_pull_list_details(list, acp_cache) {
    for (var i in list) {
        var one = list[i];
        if (one.target_resource_type.catalog_item() == "t") {
            /* FIXME: This block could stand to be a lot more elegant. */
            var call_number_el = document.getElementById(
                dom_table_rowid(one.current_resource.id()) + "_call_number"
            );
            var copy_location_el = document.getElementById(
                dom_table_rowid(one.current_resource.id()) + "_copy_location"
            );
            var bc = one.current_resource.barcode();

            if (acp_cache[bc]) {
                if (call_number_el && acp_cache[bc].call_number()) {
                    var value = acp_cache[bc].call_number().label();
                    if (value) call_number_el.innerHTML = value;
                }
                if (copy_location_el && acp_cache[bc].location()) {
                    var value = acp_cache[bc].location().name();
                    if (value) copy_location_el.innerHTML = value;
                }
            } else {
                alert(localeStrings.COPY_MISSING + bc);
            }
        }
    }
}

function populate_pull_list(form) {
    /* Step 1: get the pull list from the server. */
    try {
        var results = retrieve_pull_list(form.interval_in_days.value);
    } catch (E) {
        alert(localeStrings.PULL_LIST_ERROR + E);
        return;
    }
    if (results == null) {
        alert(localeStrings.PULL_LIST_NO_RESPONSE);
        return;
    } else if (is_ils_event(results)) {
        alert(my_ils_error(localeStrings.PULL_LIST_ERROR, results));
        return;
    }

    if (results.length) {
        reveal_dom_element(document.getElementById("table_goes_here"));
        hide_dom_element(document.getElementById("no_results"));

        /* Step 2: render the table with the pull list */
        render_pull_list_fundamentals(results);

        /* Step 3: asynchronously fill in the copy details we're missing */
        setTimeout(function() {
            var acp_cache = {};
            if ((acp_cache = get_all_relevant_acp(results)))
                fill_in_pull_list_details(results, acp_cache);
        }, 0);
    } else {
        hide_dom_element(document.getElementById("table_goes_here"));
        reveal_dom_element(document.getElementById("no_results"));
    }

}

function my_init() {
    hide_dom_element(document.getElementById("table_goes_here"));
    hide_dom_element(document.getElementById("no_results"));
    init_owning_lib_selector();
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));
}

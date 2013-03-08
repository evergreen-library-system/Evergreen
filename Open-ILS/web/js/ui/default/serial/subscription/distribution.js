/* Build maps of sre details for both display and selection purposes */

function build_sre_maps(grid) {
    try {
        //grid.sre_id_map = {};
        grid.sres_ou_map = {};
        var parent_g = window.parent.parent.g;
        if (parent_g.mfhd) {
            var mfhd_details = parent_g.mfhd.details;
            for (var i = 0; i < mfhd_details.length; i++) {
                var mfhd_detail = {};
                for (j in mfhd_details[i]) {
                    mfhd_detail[j] = mfhd_details[i][j];
                }
                var entry = {};
                entry.label = mfhd_detail.label + ' (' + (mfhd_detail.entryNum + 1) + ')';
                entry.record_entry = mfhd_detail.id;
                var org_unit_id = mfhd_detail.owning_lib;
                //grid.sre_id_map[sre_id] = mfhd_detail;
                if (!grid.sres_ou_map[org_unit_id]) {
                    grid.sres_ou_map[org_unit_id] = 
                        {
                            "identifier": "record_entry",
                            "label": "label",
                            "items": []
                        };
                }
                grid.sres_ou_map[org_unit_id].items.push(entry);
            }

            for (i in grid.sres_ou_map) {
                grid.sres_ou_map[i] = new dojo.data.ItemFileReadStore({
                    "data": grid.sres_ou_map[i]
                });
            }
        }
    } catch(E) {
        alert(E); //XXX
    }
}


function populate_sre_selector(grid, holding_lib_id, temp) {
    if (grid.sres_ou_map[holding_lib_id]) {
        grid.overrideEditWidgets.record_entry.attr
            ("store", grid.sres_ou_map[holding_lib_id]);
        grid.overrideEditWidgets.record_entry.shove = {};
        grid.overrideEditWidgets.record_entry.attr("disabled", false);
        // this is needed to reload the value after we change the store
        // XXX is there a better way to do this?
        grid.overrideEditWidgets.record_entry.setValue
            (grid.overrideEditWidgets.record_entry._lastQuery);
    } else {
        grid.overrideEditWidgets.record_entry.attr
            ("store", grid.empty_store);
        grid.overrideEditWidgets.record_entry.attr("disabled", true);
        grid.overrideEditWidgets.record_entry.attr("value", "");
    }
}


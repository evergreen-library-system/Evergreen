dojo.require("dijit.form.Form");
dojo.require("dijit.form.Button");
dojo.require("dijit.form.RadioButton");
dojo.require("dijit.form.TextBox");
dojo.require("dijit.form.FilteringSelect");
dojo.require("dojo.data.ItemFileReadStore");
dojo.require("openils.User");
dojo.require("openils.Util");
dojo.require("openils.PermaCrud");
dojo.require("openils.XUL");
dojo.require("openils.widget.AutoFieldWidget");

var _searchable_by_array = ["issn", "isbn", "upc"];
var combinedAttrValueArray = [];
var liTable;

function prepareStateStore(pcrud) {
    stateSelector.store = new dojo.data.ItemFileReadStore({
        "data": {
            "label": "description",
            "identifier": "code",
            "items": [
                /* XXX i18n; Also, this list shouldn't be hardcoded here. */
                {"code": "new", "description": "New"},
                {"code": "on-order", "description": "On Order"},
                {"code": "pending-order", "description": "Pending Order"}
            ]
        }
    });
}

function prepareScalarSearchStore(pcrud) {
    attrScalarDefSelector.store = new dojo.data.ItemFileReadStore({
        "data": acqliad.toStoreData(
            pcrud.search("acqliad", {"id": {"!=": null}})
        )
    });
}

function prepareArraySearchStore(pcrud) {
    attrArrayDefSelector.store = new dojo.data.ItemFileReadStore({
        "data": acqliad.toStoreData(
            pcrud.search("acqliad", {"code": _searchable_by_array})
        )
    });
}

function prepareAgencySelector() {
    new openils.widget.AutoFieldWidget({
        "fmClass": "acqpo",
        "fmField": "ordering_agency",
        "parentNode": dojo.byId("agency_selector"),
        "orgLimitPerms": ["VIEW_PURCHASE_ORDER"],
        "dijitArgs": {"name": "agency", "required": false}
    }).build();
}

function load() {
    var pcrud = new openils.PermaCrud();

    prepareStateStore(pcrud);
    prepareScalarSearchStore(pcrud);
    prepareArraySearchStore(pcrud);

    prepareAgencySelector();

    liTable = new AcqLiTable();
    openils.Util.show("oils-acq-li-search-form-holder");
}

function toggleAttrSearchType(which, checked) {
    /* This would be cooler with a slick dispatch table instead of branchy
     * logic, but whatever... */
    if (checked) {
        if (which == "scalar") {
            openils.Util.show("oils-acq-li-search-attr-scalar", "inline");
            openils.Util.hide("oils-acq-li-search-attr-array");
        } else if (which == "array") {
            openils.Util.hide("oils-acq-li-search-attr-scalar");
            openils.Util.show("oils-acq-li-search-attr-array", "inline");
        } else {
            openils.Util.hide("oils-acq-li-search-attr-scalar");
            openils.Util.hide("oils-acq-li-search-attr-array");
        }
    }
}

var buildAttrSearchClause = {
    "array": function(v) {
        if (!v.array_def) {
            throw new Error(localeStrings.SELECT_AN_LI_ATTRIBUTE);
        }
        return {
            "attr_value_pairs":
                [[Number(v.array_def), combinedAttrValueArray]] /* [[sic]] */
        };
    },
    "scalar": function(v) {
        if (!v.scalar_def) {
            throw new Error(localeStrings.SELECT_AN_LI_ATTRIBUTE);
        }
        return {
            "attr_value_pairs":
                [[Number(v.scalar_def), v.scalar_value]] /* [[sic]] */
        };
    },
    "none": function(v) {
        //return {"attr_value_pairs": [[1, ""]]};
        return {};
    }
};

function naivelyParse(data) {
    return data.split(/[\n, ]/).filter(function(o) {return o.length > 0; });
}

function clearTerms() {
    combinedAttrValueArray = [];
    dojo.byId("records-up").innerHTML = 0;
}

function loadTermsFromFile() {
    var rawdata = openils.XUL.contentFromFileOpenDialog(
        localeStrings.LI_ATTR_SEARCH_CHOOSE_FILE
    );
    if (!rawdata) {
        return;
    } else if (rawdata.length > 1024 * 128) {
        /* FIXME 128k is completely arbitrary; needs researched for
         * a sane limit and should also be made configurable. Further, if
         * there's going to be a size limit, it'd be much better to apply
         * it before reading in the file at all, not now. */
        alert(localeStrings.LI_ATTR_SEARCH_TOO_LARGE);
    } else {
        try {
            combinedAttrValueArray =
                combinedAttrValueArray.concat(naivelyParse(rawdata));
            dojo.byId("records-up").innerHTML = combinedAttrValueArray.length;
        } catch (E) {
            alert(E);
        }
    }
}

function buildSearchClause(values) {
    var o = {};
    if (values.state) o.li_states = [values.state];
    if (values.agency) o.po_agencies = [Number(values.agency)];
    return o;
}

function doSearch(values) {
    var results_this_time = 0;
    liTable.reset();
    try {
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.lineitem.search.by_attributes"], {
                "params": [
                    openils.User.authtoken,
                    dojo.mixin(
                        buildAttrSearchClause[values.attr_search_type](values),
                        buildSearchClause(values)
                    ),
                    {
                        "clear_marc": true, "flesh_attrs": true,
                        "flesh_notes": true
                    }
                ],
                "async": true,
                "onresponse": function(r) {
                    var li = openils.Util.readResponse(r);
                    if (li) {
                        results_this_time++;
                        liTable.addLineitem(li);
                        liTable.show("list");
                    }
                },
                "oncomplete": function() {
                    if (results_this_time < 1) {
                        alert(localeStrings.NO_RESULTS);
                    }
                }
            }
        );
    } catch (E) {
        alert(E); // XXX
    }
}

openils.Util.addOnLoad(load);

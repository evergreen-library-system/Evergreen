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

var combinedAttrValueArray = [];
var scalarAttrSearchManager;
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
}

function prepareArraySearchStore(pcrud) {
    attrArrayDefSelector.store = new dojo.data.ItemFileReadStore({
        "data": acqliad.toStoreData(
            pcrud.search("acqliad", {"code": li_exportable_attrs})
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

function toggleAttrSearchType(which, checked) {
    /* This would be cooler with a slick dispatch table instead of branchy
     * logic, but whatever... */
    if (checked) {
        if (which == "scalar") {
            if (scalarAttrSearchManager.index < 1)
                scalarAttrSearchManager.add();
            openils.Util.show("oils-acq-li-search-attr-scalar", "inline-block");
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
        var r = scalarAttrSearchManager.buildSearchClause();
        if (r.attr_value_pairs.length < 1) {
            throw new Error(localeStrings.SELECT_AN_LI_ATTRIBUTE);
        } else {
            return r;
        }
    },
    "none": function(v) {
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
    var rawdata;

    try {
        /* FIXME 128k is completely arbitrary; needs researched for
         * a sane limit and should also be made configurable. */
        rawdata = openils.XUL.contentFromFileOpenDialog(
            localeStrings.LI_ATTR_SEARCH_CHOOSE_FILE, 1024 * 128
        );
    } catch (E) {
        alert(E);
    }

    if (rawdata) {
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

function myScalarAttrSearchManager(template_id, pcrud) {
    this.template = dojo.byId(template_id);
    this.store = new dojo.data.ItemFileReadStore({
        "data": acqliad.toStoreData(
            pcrud.search("acqliad", {"id": {"!=": null}})
        )
    });
    this.rows = {};
    this.index = 0;
};
myScalarAttrSearchManager.prototype.remove = function(n) {
    dojo.destroy("scalar_attr_holder_" + n);
    delete this.rows[n];
};
myScalarAttrSearchManager.prototype.add = function() {
    var self = this;
    var n = this.index;
    var clone = dojo.clone(this.template);
    var def = dojo.query('input[name="def"]', clone)[0];
    var value = dojo.query('input[name="value"]', clone)[0];
    var a = dojo.query('a', clone)[0];

    clone.id = "scalar_attr_holder_" + n;
    a.onclick = function() { self.remove(n); };

    this.rows[n] = [
        new dijit.form.FilteringSelect({
            "id": "scalar_def_" + n,
            "name": "scalar_def_" + n,
            "store": this.store,
            "labelAttr": "description",
            "searchAttr": "description"
        }, def),
        new dijit.form.TextBox({
            "id": "scalar_value_" + n,
            "name": "scalar_value_" + n
        }, value)
    ];

    this.index++;

    dojo.place(clone, "oils-acq-li-search-scalar-adder", "before");
    openils.Util.show(clone);
};
myScalarAttrSearchManager.prototype.buildSearchClause = function() {
    var list = [];
    for (var k in this.rows) {
        var def = this.rows[k][0].attr("value");
        var val = this.rows[k][1].attr("value");
        if (def != "" && val != "")
            list.push([Number(def), val]);
    }
    return {"attr_value_pairs": list};
};
myScalarAttrSearchManager.prototype.simplifiedPairs = function() {
    var result = {};
    for (var k in this.rows) {
        result[this.rows[k][0].attr("value")] = this.rows[k][1].attr("value");
    }
    return result;
};
myScalarAttrSearchManager.prototype.newBrief = function() {
    location.href = oilsBasePath + "/acq/picklist/brief_record?prepop=" +
        encodeURIComponent(js2JSON(this.simplifiedPairs()));
};


function load() {
    var pcrud = new openils.PermaCrud();

    prepareStateStore(pcrud);
    prepareArraySearchStore(pcrud);

    prepareAgencySelector();

    liTable = new AcqLiTable();
    scalarAttrSearchManager = new myScalarAttrSearchManager(
        "oils-acq-li-search-scalar-template", pcrud
    );

    openils.Util.show("oils-acq-li-search-form-holder");
}

openils.Util.addOnLoad(load);

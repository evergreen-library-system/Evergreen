dojo.require("dijit.form.Button");
dojo.require("openils.widget.XULTermLoader");

var termLoader = null;
var liTable = null;
var pager = null;
var usingPl = null;

function fetchRecords() {
    var data = openils.Util.uniqueElements(termLoader.attr("value"));
    var result_count = 0;
    // Don't show a total for now... This total is the total number of
    // search terms, but a user would take it to mean the total number of
    // results, which we don't have a straightfoward way of getting without
    // doing the search more that once.

    // pager.total = data.length;

    progressDialog.show(true);
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.biblio.create_by_id"], {
            "params": [
                openils.User.authtoken,
                data.slice(
                    pager.displayOffset,
                    pager.displayOffset + pager.displayLimit
                ), {
                    "flesh_attrs": true,
                    "flesh_cancel_reason": true,
                    "flesh_notes": true,
                    "reuse_picklist": usingPl
                }
            ],
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (typeof(r) != "object") {
                        usingPl = r;
                    } else if (r.classname && r.classname == "jub") {
                        result_count++;
                        liTable.addLineitem(r);
                    }
                    /* The ML method is buggy and sometimes responds with
                     * more objects that we don't want, hence the specific
                     * conditionals above that don't necesarily consume all
                     * responses. */
                }
            }
        }
    );
    pager.batch_length = result_count;
    progressDialog.hide();
}

function beginSearch() {
    var data = termLoader.attr("value");
    if (!data || !data.length) {
        alert(localeStrings.LOAD_TERMS_FIRST);
        return;
    }

    pager.go(0);
    openils.Util.hide("acq-frombib-upload-box");
    openils.Util.show("acq-frombib-reload-box");
}

function init() {
    new openils.widget.XULTermLoader(
        {"parentNode": "acq-frombib-upload", "parseCSV": true}
    ).build(function(w) { termLoader = w; });

    liTable = new AcqLiTable();
    liTable.enableActionsDropdownOptions("vp");

    pager = new LiTablePager(fetchRecords, liTable);

    openils.Util.show("acq-frombib-begin-holder");
}

openils.Util.addOnLoad(init);

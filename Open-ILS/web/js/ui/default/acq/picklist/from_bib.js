dojo.require("dijit.form.Button");
dojo.require("openils.widget.XULTermLoader");

var termLoader = null;
var liTable = null;
var pager = null;
var usingPl = null;

function fetchRecords(offset, limit) {
    var data = termLoader.attr("value");
    var results = [];
    var total = data.length;
    if (offset < 0 || offset >= data.length) return [results, total];

    progressDialog.show(true);
    /* notice this call is synchronous */
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.biblio.create_by_id"], {
            "params": [
                openils.User.authtoken, data.slice(offset, offset + limit), {
                    "flesh_attrs": true,
                    "flesh_cancel_reason": true,
                    "flesh_notes": true,
                    "reuse_picklist": usingPl
                }
            ],
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (typeof(r) != "object")
                        usingPl = r;
                    else if (r.classname && r.classname == "jub")
                        results.push(r);
                    /* XXX the ML method is buggy and sometimes responds with
                     * more objects that we don't want, hence the specific
                     * conditionals above that don't necesarily consume all
                     * responses. */
                }
            }
        }
    );
    progressDialog.hide();
    return [results, total];
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
        {"parentNode": "acq-frombib-upload"}
    ).build(function(w) { termLoader = w; });
    liTable = new AcqLiTable();
    pager = new LiTablePager(fetchRecords, liTable);

    openils.Util.show("acq-frombib-begin-holder");
}

openils.Util.addOnLoad(init);

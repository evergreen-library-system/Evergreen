dojo.require("openils.acq.Lineitem");
dojo.require("openils.Util");
dojo.require("openils.XUL");

var liTable;

function attrDefByName(attr) {
    return openils.acq.Lineitem.attrDefs[
        attr.attr_type().replace(/lineitem_(.*)_attr_definition/, "$1")
    ].filter(
        function(o) { return (o.code() == attr.attr_name()); }
    ).pop();
}

function drawLiInfo(li) {
    var infoTbody = dojo.byId("acq-related-info-tbody");
    var infoRow = infoTbody.removeChild(dojo.byId("acq-related-info-row"));

    li.attributes().forEach(
        function(attr) {
            var row = dojo.clone(infoRow);

            nodeByName("label", row).innerHTML =
                attrDefByName(attr).description();
            nodeByName("value", row).innerHTML = attr.attr_value();

            infoTbody.appendChild(row);

            if (["title", "author"].indexOf(attr.attr_name()) != -1) {
                nodeByName(
                    attr.attr_name(), dojo.byId("acq-related-mini-display")
                ).innerHTML = attr.attr_value();
            }
        }
    );
}

function fetchLi() {
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve"], {
            "async": true,
            "params": [openils.User.authtoken, liId, {
                "flesh_attrs": true,
                "flesh_li_details": true,
                "flesh_fund_debit": true
            }],
            "oncomplete": function(r) {
                drawLiInfo(openils.Util.readResponse(r));
            }
        }
    );
}

function hideDetails() {
    openils.Util.show("acq-related-mini");
    openils.Util.hide("acq-related-info-div");
}

function showDetails() {
    openils.Util.show("acq-related-info-div");
    openils.Util.hide("acq-related-mini");
}

function fetchRelated() {
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitems_for_bib.by_lineitem_id"], {
            "async": true,
            "params": [openils.User.authtoken, liId, {
                "flesh_attrs": true, "flesh_notes": true
            }],
            "onresponse": function(r) {
                var resp = openils.Util.readResponse(r);
                if (resp) {
                    liTable.show("list");
                    liTable.addLineitem(resp);
                }
            }
        }
    );
}
function load() {
    openils.acq.Lineitem.fetchAttrDefs(fetchLi);
    dojo.byId("acq-related-info-back-button").onclick = hideDetails;
    dojo.byId("acq-related-info-show-button").onclick = showDetails;

    liTable = new AcqLiTable();
    liTable.reset();
    liTable._isRelatedViewer = true;

    fetchRelated();
}

openils.Util.addOnLoad(load);

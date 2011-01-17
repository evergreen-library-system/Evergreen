dojo.require("openils.widget.EditDialog");
dojo.require("openils.widget.EditPane");

var editDialog;

function toPoListing() {
    location.href = oilsBasePath + "/acq/search/unified?ca=po";
}

function toOnePo(id) {
    location.href = oilsBasePath + "/acq/po/view/" + id;
}

openils.Util.addOnLoad(
    function() {
        editDialog = new openils.widget.EditDialog({
            "editPane": new openils.widget.EditPane({
                "fmObject": new acqpo(),
                /* After realizing how many fields should be excluded from this
                 * interface because users shouldn't set them arbitrarily,
                 * it hardly seems like using these Edit widgets gives much
                 * much advantage over a hardcoded interface. */
                "suppressFields": [
                    "create_time", "edit_time", "editor", "order_date",
                    "owner", "cancel_reason", "creator", "state", "name"
                ],
                "fieldOrder": ["ordering_agency", "provider"],
                "mode": "create",
                overrideWidgetArgs : {
                    provider : { dijitArgs : { store_options : { base_filter : { active :"t" } } } },
                    ordering_agency : { orgDefaultsToWs : true }
                },
                "onSubmit": function(po) {
                    fieldmapper.standardRequest(
                        ["open-ils.acq", "open-ils.acq.purchase_order.create"],{
                            "async": false,
                            "params": [openils.User.authtoken, po],
                            "onresponse": function(r) {
                                toOnePo(
                                    openils.Util.readResponse(r).
                                    purchase_order.id()
                                );
                            }
                        }
                    );
                },
                "onCancel": function() {
                    editDialog.hide();
                    toPoListing();
                    /* I'd rather do window.close() or xulG.close_tab(),
                     * but neither of those seem to work here. */
                }
            })
        });
        editDialog.startup();
        editDialog.show();
    }
);

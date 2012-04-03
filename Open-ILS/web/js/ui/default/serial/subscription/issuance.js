dojo.require("dijit.form.DateTextBox");

function fresh_scap_selector(grid) {
    /* this really needs to be sync, not async */
    pcrud.search(
        "scap", {"subscription": sub_id, "active": "t"}, {
            "timeout": 10,
            "oncomplete": function(r) {
                var data = scap.toStoreData(openils.Util.readResponse(r));
                var selector = new dijit.form.FilteringSelect(
                    {
                        "store": new dojo.data.ItemFileReadStore({"data":data}),
                        "searchAttr": "id"
                    },
                    dojo.create("span")
                );
                selector.shove = {
                    "create": data.items.length ? data.items[0].id : ""
                };
                dojo.connect(
                    selector, "onChange", null, function() {
                        if (this.item) {
                            var widget =
                                grid.overrideEditWidgets.holding_type;
                            widget.attr("value", this.item.type);
                            widget.attr("disabled", true);
                        }
                    }
                );

                grid.overrideEditWidgets.caption_and_pattern = selector;
                if (grid.overrideEditWidgets.holding_code) {
                    grid.overrideEditWidgets.holding_code.update_scap_selector(
                        selector
                    );
                } else {
                    grid.overrideEditWidgets.holding_code =
                        new openils.widget.HoldingCode({
                            "scap_selector": selector
                        });
                    grid.overrideEditWidgets.holding_code.shove = {
                        "create": "[]"
                    };
                    grid.overrideEditWidgets.holding_code.startup();
                }

                grid.overrideEditWidgets.date_published =
                    new dijit.form.DateTextBox();
                grid.overrideEditWidgets.date_published.shove = {};
                grid.overrideEditWidgets.holding_code.date_widget =
                    grid.overrideEditWidgets.date_published;
            }
        }
    );
}

function prepare_prediction_dialog() {
    if (sub.end_date()) {
        prediction_dialog_end_date.attr("disabled", false);
        prediction_dialog_end_date.attr("checked", true);
    } else {
        prediction_dialog_end_num.attr("checked", true);
        prediction_dialog_end_date.attr("disabled", true);
        prediction_dialog_num_to_predict.focus();
    }
    prediction_dialog_submit.attr("disabled", false);
}

function generate_predictions(fields) {
    var args = {"ssub_id": sub.id()};

    if (fields.end_how == "date") {
        args.end_date = sub.end_date();
    } else if ((num = Number(fields.num_to_predict)) > 0)  {
        args.num_to_predict = num;
    } else {
        alert("Go with a whole, positive number."); /* XXX i18n */
        return;
    }

    progress_dialog.show(true);
    try {
        fieldmapper.standardRequest(
            ["open-ils.serial", "open-ils.serial.make_predictions"], {
                "params": [openils.User.authtoken, args],
                "async": true,
                "onresponse": function(r) {
                    openils.Util.readResponse(r); /* tests for events */
                },
                "oncomplete": function() {
                    progress_dialog.hide();
                    iss_grid.refresh();
                }
            }
        );
    } catch (E) {
        alert(E);
        progess_dialog.hide();
    }
}

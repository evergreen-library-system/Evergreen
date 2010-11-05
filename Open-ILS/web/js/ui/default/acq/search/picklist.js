dojo.require("dojo.data.ItemFileWriteStore");
dojo.require("dijit.Dialog");
dojo.require("dijit.form.Button");
dojo.require("dijit.form.TextBox");
dojo.require("dijit.form.FilteringSelect");
dojo.require("dijit.form.Button");
dojo.require("dojox.grid.cells.dijit");
dojo.require("openils.acq.Picklist");
dojo.require("openils.widget.ProgressDialog");

function getPlOwnerName(rowIndex, item) {
    try {
        return resultManager.plCache[this.grid.store.getValue(item, "id")].
            owner().usrname();
    } catch (E) {
        return "";
    }
}

function formatPlName(pl) {
    if (pl) {
        return "<a href='" + oilsBasePath + "/acq/picklist/view/" +
            pl.id + "'>" + pl.name + "</a>";
    }
}

function deleteSelectedPl() {
    var grid = resultManager.result_types.picklist.interface;

    progressDialog.show(true);

    openils.acq.Picklist.deleteList(
        grid.getSelectedItems().map(
            function(item) {
                var id = grid.store.getValue(item, "id");
                grid.store.deleteItem(item);
                return id;
            }
        ), function() { progressDialog.hide(); }
    );
}

function cloneSelectedPl(fields) {
    var grid = resultManager.result_types.picklist.interface;

    var item = grid.getSelectedItems()[0];
    if (!item) return;

    var plId = grid.store.getValue(item, "id");
    var entryCount = Number(grid.store.getValue(item, "entry_count"));

    progressDialog.show();
    progressDialog.update({"maximum": entryCount, "progress": 0});

    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.picklist.clone"], {
            "async": true,
            "params": [openils.User.authtoken, plId, fields.name],
            "onresponse": function(r) {
                var resp = openils.Util.readResponse(r);
                if (resp) {
                    progressDialog.update({"progress": resp.li});

                    if (resp.complete) {
                        progressDialog.hide();
                        var pl = resp.picklist;
                        pl.owner(openils.User.user);
                        pl.entry_count(entryCount);
                        resultManager.plCache[pl.id()] = pl;
                        grid.store.newItem(fieldmapper.acqpl.toStoreItem(pl));
                    }
                }
            }
        }
    );
}

function loadLeadPlSelector() {
    var grid = resultManager.result_types.picklist.interface;
    var data = acqpl.initStoreData();
    var store = new dojo.data.ItemFileWriteStore({"data": data});

    grid.getSelectedItems().forEach(
        function(item) {
            store.newItem(
                fieldmapper.acqpl.toStoreItem(
                    resultManager.plCache[grid.store.getValue(item, "id")]
                )
            );
        }
    );

    plMergeLeadSelector.store = store;
    plMergeLeadSelector.startup();
}

function mergeSelectedPl(fields) {
    var grid = resultManager.result_types.picklist.interface;

    if (!fields.lead) return;

    var ids = [];
    var totalLi = 0;
    var leadPl = resultManager.plCache[fields.lead];
    var leadPlItem;

    grid.getSelectedItems().forEach(
        function(item) {
            var id = grid.store.getValue(item, "id");
            if (id == fields.lead) {
                leadPlItem = item;
                return;
            }
            totalLi +=  new Number(grid.store.getValue(item, "entry_count"));
            ids.push(id);
        }
    );

    progressDialog.show();
    progressDialog.update({"maximum": totalLi, "progress": 0});

    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.picklist.merge"], {
            "async": true,
            "params": [openils.User.authtoken, fields.lead, ids],
            "onresponse": function(r) {
                var resp = openils.Util.readResponse(r);
                if (resp) {
                    if (resp.li)
                        progressDialog.update({"progress": resp.li});

                    if (resp.complete) {
                        progressDialog.hide();
                        leadPl.entry_count(leadPl.entry_count() + totalLi);

                        grid.store.setValue(
                            leadPlItem, "entry_count", leadPl.entry_count()
                        );
                        if (resp.picklist) {
                            grid.store.setValue(
                                leadPlItem, "edit_time",
                                resp.picklist.edit_time()
                            );
                        }

                        // remove the deleted lists from the grid
                        grid.getSelectedItems().filter(
                            function(o) {
                                return grid.store.getValue(o, "id") !=
                                    fields.lead;
                            }
                        ).forEach(function(o) { grid.store.deleteItem(o); });
                    }
                }
            }
        }
    );
}

function createPl(fields) {
    if (fields.name == '') return;

    var grid = resultManager.result_types.picklist.interface;

    openils.acq.Picklist.create(fields,
        function(plId) {
            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.picklist.retrieve.authoritative"], {
                    "async": true,
                    "params": [
                        openils.User.authtoken, plId,
                        {"flesh_lineitem_count": 1, "flesh_owner": 1}
                    ],
                    "oncomplete": function(r) {
                        var pl = openils.Util.readResponse(r);
                        if (pl) {
                            resultManager.plCache[pl.id()] = pl;
                            grid.store.newItem(
                                acqpl.toStoreData([pl]).items[0]
                            );
                        }
                    }
                }
            );
        }
    );
}


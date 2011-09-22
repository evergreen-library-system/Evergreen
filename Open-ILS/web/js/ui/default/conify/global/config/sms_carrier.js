dojo.require('dojox.grid.DataGrid');
dojo.require('openils.widget.AutoGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.Dialog');
dojo.require('openils.PermaCrud');

var thingList;

function thingInit() {

    thingGrid.disableSelectorForRow = function(rowIdx) {
        var item = thingGrid.getItem(rowIdx);
        return (thingGrid.store.getValue(item, 'id') < 0);
    }

    buildGrid();
}

function buildGrid() {

    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.csc.atomic'],
        {   async: true,
            params: [
                openils.User.authtoken,
                {"id":{"!=":null}},
                {"order_by":{"csc":"name"}}
            ],
            oncomplete: function(r) {
                if(thingList = openils.Util.readResponse(r)) {
                    thingList = openils.Util.objectSort(thingList,'name');
                    dojo.forEach(thingList,
                                 function(e) {
                                     thingGrid.store.newItem(csc.toStoreItem(e));
                                 }
                                );
                }
            }
        }
    );
}

openils.Util.addOnLoad(thingInit);



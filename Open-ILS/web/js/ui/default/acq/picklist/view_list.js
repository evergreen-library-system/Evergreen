dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.Button');
dojo.require('openils.acq.Picklist');
dojo.require('openils.Util');

var listAll = false;

function loadGrid() {
    var method = 'open-ils.acq.picklist.user.retrieve';
    if(listAll)
        method = method.replace(/user/, 'user.all');

    //var store = new dojo.data.ItemFileWriteStore({data:acqpl.toStoreData([])});
    var store = new dojo.data.ItemFileWriteStore({data:acqpl.initStoreData()});
    plListGrid.setStore(store);
    plListGrid.render();

    fieldmapper.standardRequest(
        ['open-ils.acq', method],

        {   async: true,
            params: [openils.User.authtoken, 
                {flesh_lineitem_count:1, flesh_username:1}],

            onresponse : function(r) {
                if(pl = openils.Util.readResponse(r)) 
                    store.newItem(acqpl.itemToStoreData(pl));
            }
        }
    );
}

function createPL(fields) {
    if(fields.name == '') return;

    openils.acq.Picklist.create(fields,

        function(plId) {
            fieldmapper.standardRequest(

                ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
                {   async: true,
                    params: [openils.User.authtoken, plId,
                        {flesh_lineitem_count:1, flesh_username:1}],

                    oncomplete: function(r) {
                        if(pl = openils.Util.readResponse(r)) 
                           plListGrid.store.newItem(acqpl.toStoreData([pl]).items[0]);
                    }
                }
            );
        }
    );
}

function deleteFromGrid() {
    var list = []
    var selected = plListGrid.selection.getSelected();
    for(var idx = 0; idx < selected.length; idx++) {
        var item = selected[idx];
        list.push(item.id);
        plListGrid.store.deleteItem(item);
    }
    openils.acq.Picklist.deleteList(list);
}

openils.Util.addOnLoad(loadGrid);



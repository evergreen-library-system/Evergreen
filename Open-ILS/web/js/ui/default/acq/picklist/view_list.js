dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.cells.dijit');
dojo.require('openils.acq.Picklist');
dojo.require('openils.Util');

var listAll = false;
var plCache = {};

function loadGrid() {
    var method = 'open-ils.acq.picklist.user.retrieve';
    if(listAll)
        method = method.replace(/user/, 'user.all');

    var store = new dojo.data.ItemFileWriteStore({data:acqpl.initStoreData()});
    plListGrid.setStore(store);
    plListGrid.render();
    dojo.connect(store, 'onSet', plGridChanged);

    fieldmapper.standardRequest(
        ['open-ils.acq', method],

        {   async: true,
            params: [openils.User.authtoken, 
                {flesh_lineitem_count:1, flesh_owner:1}],

            onresponse : function(r) {
                if(pl = openils.Util.readResponse(r)) {
                    plCache[pl.id()] = pl;
                    store.newItem(acqpl.toStoreItem(pl));
                }
            }
        }
    );
}
function getOwnerName(rowIndex, item) {
    if(!item) return ''; 
    var id= this.grid.store.getValue(item, 'id'); 
    var pl = plCache[id];
    return pl.owner().usrname();
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
function plGridChanged(item, attr, oldVal, newVal) {
    var pl = plCache[plListGrid.store.getValue(item, 'id')];
    console.log("changing pl " + pl.id() + " object: " + attr + " = " + newVal);
    pl[attr](newVal);
    pl.ischanged(true);
    plSaveButton.setDisabled(false);
}
function saveChanges() {
    plListGrid.doclick(0);   
    var changedObjects = [];
    for(var i in plCache){
        var pl = plCache[i];
        if(pl.ischanged())
            changedObjects.push(pl);
    }   
    _saveChanges(changedObjects, 0);
}
function _saveChanges(changedObjects, idx) {
    
    if(idx >= changedObjects.length) {
        // we've made it through the list
        plSaveButton.setDisabled(true);
        return;
    }

    var pl = changedObjects[idx];
    var owner = pl.owner();
    pl.owner(owner.id()); // un-flesh the owner object

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.update'],
        {   async: true,
            params: [openils.User.authtoken, pl],
            oncomplete: function(r) {
                if(stat = openils.Util.readResponse(r)) {
                    _saveChanges(changedObjects, ++idx);
                }
            }
        }
    );
}

function getDateTimeField(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, this.field);
    var date = dojo.date.stamp.fromISOString(data);
    return dojo.date.locale.format(date, {formatLength:'short'});
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



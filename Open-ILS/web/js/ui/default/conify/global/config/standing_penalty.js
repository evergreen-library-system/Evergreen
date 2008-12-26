dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('dijit.form.TextBox');
dojo.require('dojox.grid.cells.dijit');

 var spCache = {};

function spBuildGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:csp.initStoreData()});
    spGrid.setStore(store);
    spGrid.render();
    dojo.connect(store, 'onSet', spGridChanged);

    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.csp'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}, {order_by:{csp:'id'}}],
            onresponse: function(r) {
                if(sp = openils.Util.readResponse(r)) 
                    store.newItem(csp.itemToStoreData(sp));
                spCache[sp.id()] = sp;
            } 
        }
    );
}

function spCreate(args) {
    if(!(args.name && args.label)) return;

    var penalty = new csp();
    penalty.name(args.name);
    penalty.label(args.label);
    penalty.block_list(args.block_list); 

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.csp'],
        { async: true,
          params: [openils.User.authtoken, penalty],
          oncomplete: function(r) {
              if(obj = openils.Util.readResponse(r))
                  spGrid.store.newItem(csp.itemToStoreData(obj));
            }
        }
    );
}
function spGridChanged(item, attr, oldVal, newVal) {
    var sp = spCache[spGrid.store.getValue(item, 'id')];
    console.log("changing cm " + sp.id() + " object: " + attr + " = " + newVal);
    sp[attr](newVal);
    sp.ischanged(true);
    spSaveButton.setDisabled(false);
}
function saveChanges() {
    spGrid.doclick(0);   
    var changedObjects = [];
    for(var i in spCache){
        var sp = spCache[i];
        if(sp.ischanged())
            changedObjects.push(sp);
    }   
    _saveChanges(changedObjects, 0);
}
function _saveChanges(changedObjects, idx) {
    
    if(idx >= changedObjects.length) {
        // we've made it through the list
        spSaveButton.setDisabled(true);
        return;
    }

    var item = changedObjects[idx];
         
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.update.csp'],
        {   async: true,
            params: [openils.User.authtoken, item],
            oncomplete: function(r) {
                if(stat = openils.Util.readResponse(r)) {
                    _saveChanges(changedObjects, ++idx);
                }
            }
        }
    );
}

function formatId(inDatum) {
    if(inDatum < 100){
        return "<span style='color:red;'>"+ inDatum +"</span>";
    }
    return inDatum;
        
}
function deleteFromGrid() {
        _deleteFromGrid(spGrid.selection.getSelected(), 0);
}   

function _deleteFromGrid(list, idx) {
    if(idx >= list.length) // we've made it through the list
        return;

    var item = list[idx];
    var id = spGrid.store.getValue(item, 'id');

    if(id < 100) { // don't delete system penalties
        _deleteFromGrid(list, ++idx);
        return;
    }

    fieldmapper.standardRequest(
       ['open-ils.permacrud', 'open-ils.permacrud.delete.csp'],
       {    async: true,
            params: [openils.User.authtoken, id],
            oncomplete: function(r) {
                if(obj = openils.Util.readResponse(r)) {
                    spGrid.store.deleteItem(item);
                }
                _deleteFromGrid(list, ++idx);
            }
        }
    );
}

openils.Util.addOnLoad(spBuildGrid);



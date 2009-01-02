dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');

function buildHMGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:chmm.initStoreData('id', {identifier:'id'})})
    hmGrid.setStore(store);
    hmGrid.render();
    // dojo.connect(store, 'onSet', cmGridChanged);
    console.log(js2JSON(store));
    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.chmm'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}],
            onresponse: function (r) {
                console.log('blah');
                if(obj = openils.Util.readResponse(r)) {
                    store.newItem(chmm.itemToStoreData(obj));
                    // cmCache[obj.code()] = obj;
                }
           }
        }
    );
}

openils.Util.addOnLoad(buildHMGrid);
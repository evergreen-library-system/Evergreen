dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CheckBox');

function buildCMGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:ccm.initStoreData('code', {identifier:'code'})})
    cmGrid.setStore(store);
    cmGrid.render();

    fieldmapper.standardRequest(
       ['open-ils.permacrud', 'open-ils.permacrud.search.ccm'],
       {   async: true,
               params: [openils.User.authtoken, {code:{'!=':null}}],
               onresponse: function (r) { 
               if(obj = openils.Util.readResponse(r)) {
                   store.newItem(ccm.itemToStoreData(obj));
                   
               }
           }
       }
    );
}

function getMagneticMedia(rowIdx, item) {
    if(!item) return '';
    var magMed = this.grid.store.getValue(item, this.field);
    if(openils.Util.isTrue(magMed))
        return "<span style='color:green;'>&#x2713;</span>";
    return "<span style='color:red;'>&#x2717;</span>";
}

    
openils.Util.addOnLoad(buildCMGrid);


dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');

var cmCache = {};

function buildCMGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:ccm.initStoreData('code', {identifier:'code'})})
    cmGrid.setStore(store);
    cmGrid.render();
    dojo.connect(store, 'onSet', cmGridChanged);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.ccm'],
        {   async: true,
            params: [openils.User.authtoken, {code:{'!=':null}}],
            onresponse: function (r) { 
                if(obj = openils.Util.readResponse(r)) {
                    store.newItem(ccm.itemToStoreData(obj));
                    cmCache[obj.code()] = obj;
                }
           }
        }
    );
}

function cmGridChanged(item, attr, oldVal, newVal) {
    var cm = cmCache[cmGrid.store.getValue(item, 'code')];
    console.log("changing cm " + cm.code() + " object: " + attr + " = " + newVal);
    cm[attr](newVal);
    cm.ischanged(true);
    cmSaveButton.setDisabled(false);
}

function saveChanges() {
    cmGrid.doclick(0); // force still-focused changes
    /* loop through the changed objects in cmCache and update them in the DB */
}

function getMagneticMedia(rowIdx, item) {
    if(!item) return '';
    var magMed = this.grid.store.getValue(item, this.field);
    if(openils.Util.isTrue(magMed))
        return "<span style='color:green;'>&#x2713;</span>";
    return "<span style='color:red;'>&#x2717;</span>";
}

function cmCreate(args) {
    if(! (args.code && args.name && args.description && args.sip2_media_type)) 
        return;

    var cmod = new ccm();
    cmod.code(args.code);
    cmod.name(args.name);
    cmod.description(args.description);
    cmod.sip2_media_type(args.sip2_media_type);
    if(args.magnetic_media[0] == 'on')
        cmod.magnetic_media('t')
    else
        cmod.magnetic_media('f');

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.ccm'],
        {   async: true,
            params: [openils.User.authtoken, cmod],
            oncomplete: function(r) {
                if(cm = openils.Util.readResponse(r))
                    cmGrid.store.newItem(ccm.itemToStoreData(cm));
            }
        }
    );
}

function deleteFromGrid() {
    _deleteFromGrid(cmGrid.selection.getSelected(), 0);
}   

function _deleteFromGrid(list, idx) {
    if(idx >= list.length) // we've made it through the list
        return;

    var item = list[idx];
    var code = cmGrid.store.getValue(item, 'code');

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.delete.ccm'],
        {   async: true,
            params: [openils.User.authtoken, code],
            oncomplete: function(r) {
                if(stat = openils.Util.readResponse(r)) {
                    // delete succeeded, remove it from the grid and the local cache
                    cmGrid.store.deleteItem(item); 
                    delete cmCache[item.code];
                }
                _deleteFromGrid(list, ++idx);
            }
        }
    );
}

openils.Util.addOnLoad(buildCMGrid);



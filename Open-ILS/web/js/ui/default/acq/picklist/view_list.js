dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.cells.dijit');
dojo.require('openils.acq.Picklist');
dojo.require('openils.Util');
dojo.require('openils.widget.ProgressDialog');

var listAll = false;
var plCache = {};

function loadGrid() {

    dojo.connect(plMergeDialog, 'onOpen', function(){loadLeadPlSelector();});

    var method = 'open-ils.acq.picklist.user.retrieve';
    if(listAll)
        method = method.replace(/user/, 'user.all');

    var store = new dojo.data.ItemFileWriteStore({data:acqpl.initStoreData()});
    plListGrid.setStore(store);
    plListGrid.render();

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
            }, 
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

function cloneSelectedPl(fields) {

    var selected = plListGrid.selection.getSelected();
    if(selected.length == 0 || !(fields.name)) return;

    var item = selected[0]; // clone the first selected
    var plId = plListGrid.store.getValue(item, 'id');
    var entryCount = Number(plListGrid.store.getValue(item, 'entry_count'));

    progressDialog.show();
    progressDialog.update({maximum:entryCount, progress:0});

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.clone'],
        {   async: true,
            params: [openils.User.authtoken, plId, fields.name],

            onresponse : function(r) {
                var resp = openils.Util.readResponse(r);
                if(!resp) return;
                progressDialog.update({progress:resp.li});

                if(resp.complete) {
                    progressDialog.hide();
                    var pl = resp.picklist;
                    plCache[pl.id()] = pl;
                    pl.owner(openils.User.user);
                    pl.entry_count(entryCount);
                    plListGrid.store.newItem(fieldmapper.acqpl.toStoreItem(pl));
                }
            }
        }
    );
}

function loadLeadPlSelector() {
    var store = new dojo.data.ItemFileWriteStore({data:acqpl.initStoreData()}); 
    var selected = plListGrid.selection.getSelected();
    dojo.forEach(selected, function(item) { 
        var pl = plCache[plListGrid.store.getValue(item, 'id')];
        store.newItem(fieldmapper.acqpl.toStoreItem(pl));
    });
    plMergeLeadSelector.store = store;
    plMergeLeadSelector.startup();
}

function mergeSelectedPl(fields) {
    if(!fields.lead) return;

    var ids = [];
    var totalLi = 0;
    var selected = plListGrid.selection.getSelected();
    var leadPl = plCache[fields.lead];
    var leadPlItem;

    dojo.forEach(selected, function(item) { 
        var id = plListGrid.store.getValue(item, 'id');
        if(id == fields.lead) {
            leadPlItem = item;
            return;
        }
        totalLi +=  new Number(plListGrid.store.getValue(item, 'entry_count'));
        ids.push(id);
    });

    progressDialog.show();
    progressDialog.update({maximum:totalLi, progress:0});

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.merge'],
        {   async: true,
            params: [openils.User.authtoken, fields.lead, ids],
            onresponse : function(r) {
                var resp = openils.Util.readResponse(r);
                if(!resp) return;
                progressDialog.update({progress:resp.li});

                if(resp.complete) {
                    progressDialog.hide();
                    leadPl.entry_count( leadPl.entry_count() + totalLi );
                    plListGrid.store.setValue(leadPlItem, 'entry_count', leadPl.entry_count());

                    // remove the deleted lists from the grid
                    dojo.forEach(selected, function(item) { 
                        var id = plListGrid.store.getValue(item, 'id');
                        if(id != fields.lead)
                            plListGrid.store.deleteItem(item);
                    });
                }
            }
        }
    );
}

openils.Util.addOnLoad(loadGrid);



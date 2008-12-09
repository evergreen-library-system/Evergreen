dojo.require('dojox.grid.DataGrid');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.Button');
dojo.require('openils.acq.Picklist');
dojo.require('openils.Util');

var plList = [];
var listAll = false;

function makeGridFromList() {
    var store = new dojo.data.ItemFileReadStore({data:acqpl.toStoreData(plList)});
    plListGrid.setStore(store);
    plListGrid.render();
}


function loadGrid() {
    var method = 'open-ils.acq.picklist.user.retrieve.atomic';
    if(listAll)
        method = method.replace(/user/, 'user.all');

    fieldmapper.standardRequest(
        ['open-ils.acq', method],
        {   async: true,
            params: [openils.User.authtoken, 
                {flesh_lineitem_count:1, flesh_username:1}],
            oncomplete: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                plList = resp;
                makeGridFromList();
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
                        var pl = r.recv().content();
                        plList.push(pl);
                        makeGridFromList();
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
        var rowIdx = selected[idx];
        var id = plListGrid.model.getRow(rowIdx).id;
        for(var i = 0; i < plList.length; i++) {
            var pl = plList[i];
            if(pl.id() == id && pl.owner() == new openils.User().user.usrname()) {
                list.push(id);
                plList = (plList.slice(0, i) || []).concat(plList.slice(i+1, plList.length) || []);
            }
        }
    }
    openils.acq.Picklist.deleteList(list, function() { makeGridFromList(); });
}

openils.Util.addOnLoad(loadGrid);



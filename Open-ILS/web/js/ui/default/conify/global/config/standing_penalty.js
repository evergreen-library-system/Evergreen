dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('dijit.form.TextBox');

function spBuildGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:csp.toStoreData([])});
    spGrid.setStore(store);
    spGrid.render();
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.csp'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}, {order_by:{csp:'id'}}],
            onresponse: function(r) {
                if(sp = openils.Util.readResponse(r)) 
                    store.newItem(csp.toStoreData([sp]).items[0]);
            }, 
        }
    );
}

function spCreate(args) {
    if(!(args.name && args.label)) return;

    var penalty = new csp();
    penalty.name(args.name);
    penalty.label(args.label);

    var str = '';
    for(var idx in args.block_list)
        str += args.block_list[idx] + '|';
    str = str.replace(/\|$/, '');
    penalty.block_list(str || null);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.csp'],
        {   async: true,
            params: [openils.User.authtoken, penalty],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    spBuildGrid();
            }
        }
    );
}

openils.Util.addOnLoad(spBuildGrid);



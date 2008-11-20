dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dojox.form.CheckedMultiSelect');
dojo.require('dijit.form.TextBox');

var spList;

function spBuildGrid() {
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.csp.atomic'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}],
            oncomplete: function(r) {
                if(spList = openils.Util.readResponse(r)) {
                    var store = new dojo.data.ItemFileReadStore({data:csp.toStoreData(spList)});
                    spGrid.setStore(store);
                    spGrid.render();
                }
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
        {   async: true,
            params: [openils.User.authtoken, penalty],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    buildSPGrid();
            }
        }
    );
}

openils.Util.addOnLoad(spBuildGrid);



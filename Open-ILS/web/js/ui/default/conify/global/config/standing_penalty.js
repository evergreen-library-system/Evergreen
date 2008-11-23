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
                    spList = spList.sort(
                        function(a, b) {
                            if(a.id() > b.id()) 
                                return 1;
                            return -1;
                        }
                    );
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



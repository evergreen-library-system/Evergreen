dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.FilteringSelect');

var gptList;

function gptBuildGrid() {
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.pgpt.atomic'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}],
            oncomplete: function(r) {
                if(gptList = openils.Util.readResponse(r, false, true)) {
                    gptList = gptList.sort(
                        function(a, b) {
                            if(a.id() > b.id()) 
                                return 1;
                            return -1;
                        }
                    );
                    var store = new dojo.data.ItemFileReadStore({data:pgpt.toStoreData(gptList)});
                    gptGrid.setStore(store);
                    gptGrid.render();
                }
            }
        }
    );
}

function spCreate(args) {
    return alert(js2JSON(args));

    if(!(args.name && args.label)) return;

    var penalty = new pgpt();
    penalty.name(args.name);
    penalty.label(args.label);

    var str = '';
    for(var idx in args.block_list)
        str += args.block_list[idx] + '|';
    str = str.replace(/\|$/, '');
    penalty.block_list(str || null);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.pgpt'],
        {   async: true,
            params: [openils.User.authtoken, penalty],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    gptBuildGrid();
            }
        }
    );
}

openils.Util.addOnLoad(gptBuildGrid);



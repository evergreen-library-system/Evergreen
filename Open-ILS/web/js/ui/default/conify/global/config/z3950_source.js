dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var zsList;

function buildZSGrid() {
    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.czs.atomic'],
        {   async: true,
            params: [openils.User.authtoken, {name:{'!=':null}}],
            oncomplete: function(r) {
                if(zsList = openils.Util.readResponse(r)) {
                    var store = new dojo.data.ItemFileReadStore(
                        {data:czs.toStoreData(zsList, 'name',{identifier:'name'})});
                    zsGrid.setStore(store);
                    zsGrid.render();
                }
            }
        }
    );
}

function zsCreate(args) {
    return alert(js2JSON(args));
    if(!args.name || args.owner == null) 
        return;
    if(args.default_price == '' || isNaN(args.default_price))
        args.default_price = null;

    var zsype = new czs();
    zsype.name(args.name);
    zsype.owner(args.owner);
    zsype.default_price(args.default_price);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.czs'],
        {   async: true,
            params: [openils.User.authtoken, zsype],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    buildBTGrid();
            }
        }
    );
}

openils.Util.addOnLoad(buildZSGrid);



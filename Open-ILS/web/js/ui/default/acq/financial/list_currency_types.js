dojo.require("dijit.Dialog");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('fieldmapper.dojoData');

var currencyTypes = [];

function loadCTypesGrid() {
    openils.acq.CurrencyType.fetchAll(
        function(types) {
            var store = new dojo.data.ItemFileReadStore(
                {data:acqct.toStoreData(types, 'code', {identifier:'code'})});
           
            currencyTypeListGrid.setStore(store);
            currencyTypeListGrid.render();
        }
    );
}

function createCT(args) {
    if(!(args.code && args.label)) return;
    var ct = new acqct();
    ct.code(args.code);
    ct.label(args.label);
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.create.acqct'],
        {   async: true,
            params: [openils.User.authtoken, ct],
            oncomplete: function(r) {
                if(new String(openils.Util.readResponse(r)) != '0')
                    loadCTypesGrid();
            }
        }
    );
}


openils.Util.addOnLoad(loadCTypesGrid);

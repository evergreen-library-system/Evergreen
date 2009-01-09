dojo.require("dijit.Dialog");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('fieldmapper.dojoData');

var currencyTypes = [];

function loadCTypesGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:acqct.initStoreData('code', {identifier:'code'})});
    currencyTypeListGrid.setStore(store);
    currencyTypeListGrid.render();

    fieldmapper.standardRequest(
        [ 'open-ils.acq', 'open-ils.acq.currency_type.all.retrieve'],
        { async: true,
          params: [openils.User.authtoken],
          onresponse : function(r){
                if(ct = openils.Util.readResponse(r)) {
                    openils.acq.CurrencyType.cache[ct.code()] = ct;
                    store.newItem(acqct.toStoreItem(ct));
                }
            }
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

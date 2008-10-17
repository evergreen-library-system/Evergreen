dojo.require("dijit.Dialog");
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');
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
            var model = new dojox.grid.data.DojoData(null, store, 
                {rowsPerPage: 20, clientSort: true, query:{code:'*'}});
            currencyTypeListGrid.setModel(model);
            currencyTypeListGrid.update();
        }
    );
}


openils.Util.addOnLoad(loadCTypesGrid);

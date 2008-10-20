dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require("dijit.Dialog");
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.acq.Lineitem');
dojo.require('openils.acq.Provider');
dojo.require('openils.acq.PO');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var recvCount = 0;
var createAssetsSelected = false;
var createDebitsSelected = false;

var lineitems = [];

function drawForm() {
    buildProviderSelect(providerSelector);
}

function buildProviderSelect(sel, oncomplete) {
    openils.acq.Provider.createStore(
        function(store) {
            sel.store = new dojo.data.ItemFileReadStore({data:store});
            if(oncomplete)
                oncomplete();
        },
        'MANAGE_PROVIDER'
    );
}

var liReceived;
function doSearch(values) {
    var search = {};
    for(var v in values) {
        var val = values[v];
        if(val != null && val != '')
            search[v] = val;
    }

    if(values.state == 'approved')
        dojo.style('oils-acq-li-search-po-create', 'visibility', 'visible');
    else
        dojo.style('oils-acq-li-search-po-create', 'visibility', 'hidden');

    //search = [search, {limit:searchLimit, offset:searchOffset}];
    search = [search, {}];
    options = {clear_marc:1, flesh_attrs:1};

    liReceived = 0;
    lineitems = [];
    dojo.style('searchProgress', 'visibility', 'visible');
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [openils.User.authtoken, search, options],
            onresponse: handleResult,
            oncomplete: viewList
        }
    );
}

function handleResult(r) {
    var result = r.recv().content();
    searchProgress.update({maximum: searchLimit, progress: ++liReceived});
    lineitems.push(result);
}

function viewList() {
    dojo.style('searchProgress', 'visibility', 'hidden');
    dojo.style('oils-acq-li-search-result-grid', 'visibility', 'visible');
    var store = new dojo.data.ItemFileWriteStore(
        {data:jub.toStoreData(lineitems, null, 
            {virtualFields:['estimated_price', 'actual_price']})});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    JUBGrid.populate(liGrid, model, lineitems);
}

function createPOFromLineitems(fields) {
    var po = new acqpo();
    po.provider(newPOProviderSelector.getValue());
    createAssetsSelected = fields.create_assets;
    createDebitsSelected = fields.create_debits;

    if(fields.which == 'selected') {
        // find the selected lineitems
        var selected = liGrid.selection.getSelected();
        var selList = [];
        for(var idx = 0; idx < selected.length; idx++) {
            var rowIdx = selected[idx];
            var id = liGrid.model.getRow(rowIdx).id;
            for(var i = 0; i < lineitems.length; i++) {
                var li = lineitems[i];
                if(li.id() == id && !li.purchase_order() && li.state() == 'approved')
                    selList.push(lineitems[i]);
            }
        }
    } else {
        selList = lineitems;
    }

    if(selList.length == 0) return;

    openils.acq.PO.create(po, 
        function(poId) {
            if(e = openils.Event.parse(poId)) 
                return alert(e);
            updateLiList(poId, selList);
        }
    );
}

function updateLiList(poId, selList) {
    _updateLiList(poId, selList, 0);
}

function checkCreateDebits(poId) {
    if(!createDebitsSelected)
        return viewPO(poId);
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.debits.create'],
        {   async: true,
            params: [openils.User.authtoken, poId, {encumbrance:1}],
            oncomplete : function(r) {
                var total = r.recv().content();
                if(e = openils.Event.parse(total))
                    return alert(e);
                viewPO(poId);
            }
        }
    );
}

function viewPO(poId) {
    location.href = 'view/' + poId;
}

function _updateLiList(poId, selList, idx) {
    if(idx >= selList.length) {
        if(createAssetsSelected)
            return createAssets(poId);
        else
            return checkCreateDebits(poId);
    }
    var li = selList[idx];
    li.purchase_order(poId);
    li.state('in-process');
    new openils.acq.Lineitem({lineitem:li}).update(
        function(stat) {
            _updateLiList(poId, selList, ++idx);
        }
    );
}

function createAssets(poId) {
    searchProgress.update({progress: 0});
    dojo.style('searchProgress', 'visibility', 'visible');

    function onresponse(r) {
        var stat = r.recv().content();
        if(e = openils.Event.parse(stat))
            return alert(e);
        searchProgress.update({maximum: stat.total, progress: stat.progress});
    }

    function oncomplete(r) {
        dojo.style('searchProgress', 'visibility', 'hidden');
        checkCreateDebits(poId);
    }

    fieldmapper.standardRequest(
        ['open-ils.acq','open-ils.acq.purchase_order.assets.create'],
        {   async: true,
            params: [openils.User.authtoken, poId],
            onresponse : onresponse,
            oncomplete : oncomplete
        }
    );
}
    

openils.Util.addOnLoad(drawForm);


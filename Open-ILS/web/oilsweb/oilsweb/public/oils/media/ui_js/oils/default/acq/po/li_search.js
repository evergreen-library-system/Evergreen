dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.Event');
dojo.require('openils.acq.Lineitems');
dojo.require('openils.acq.Provider');

var recvCount = 0;
var user = new openils.User();

var lineitems = [];

function drawForm() {
    openils.acq.Provider.createStore(
        function(store) {
            providerSelector.store = 
                new dojo.data.ItemFileReadStore({data:store});
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

    search = [search, {limit:searchLimit, offset:searchOffset}];
    options = {clear_marc:1, flesh_attrs:1};

    liReceived = 0;
    lineitems = [];
    dojo.style('searchProgress', 'visibility', 'visible');
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [user.authtoken, search, options],
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
    var store = new dojo.data.ItemFileReadStore({data:jub.toStoreData(lineitems)});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    liGrid.setModel(model);
    liGrid.update();
}


function getProvider(rowIndex) {
    data = liGrid.model.getRow(rowIndex);
    if(!data) return;
    if(!data.provider) return '';
    return openils.acq.Provider.retrieve(data.provider).code();
}

function getLi(id) {
    for(var i in lineitems) {
        var li = lineitems[i];
        if(li.id() == id) 
            return li;
    }
}

function getJUBTitle(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return '';
    return new openils.acq.Lineitems(
        {lineitem:getLi(data.id)}).findAttr('title', 'lineitem_marc_attr_definition')
}

function getJUBIsbn(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return '';
    return new openils.acq.Lineitems(
        {lineitem:getLi(data.id)}).findAttr('isbn', 'lineitem_marc_attr_definition')
}

function getJUBPubdate(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return '';
    return new openils.acq.Lineitems(
        {lineitem:getLi(data.id)}).findAttr('pubdate', 'lineitem_marc_attr_definition')
}

function getJUBPrice(rowIndex) {
    var data = liGrid.model.getRow(rowIndex);
    if(!data) return;
    return new openils.acq.Lineitems(
        {lineitem:getLi(data.id)}).findAttr('price', 'lineitem_marc_attr_definition')
}

dojo.addOnLoad(drawForm);

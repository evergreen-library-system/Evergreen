dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require("dijit.Dialog");
dojo.require('openils.Event');
dojo.require('openils.acq.Lineitem');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var lineitems = [];

function drawForm() {
    new openils.User().buildPermOrgSelector('VIEW_PURCHASE_ORDER', orderingAgencySelector);
}
dojo.addOnLoad(drawForm);

var liReceived;
function doSearch(values) {
    var search = {
        attr_values : [values.identifier],
        po_agencies : (values.ordering_agency) ? [values.ordering_agency] : null,
        li_states : ['in-process']
    };

    options = {clear_marc:1, flesh_attrs:1};
    liReceived = 0;
    dojo.style('searchProgress', 'visibility', 'visible');

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search.ident'],
        {   async: true,
            params: [openils.User.authtoken, search, options],
            onresponse: handleResult,
            oncomplete: viewList
        }
    );
}

var searchLimit = 10; // ?
function handleResult(r) {
    var result = r.recv().content();
    searchProgress.update({maximum: searchLimit, progress: ++liReceived});
    lineitems.push(result);
}

function viewList() {
    dojo.style('searchProgress', 'visibility', 'hidden');
    dojo.style('oils-acq-li-recv-grid', 'visibility', 'visible');
    dojo.style('oils-acq-li-recv-grid', 'display', 'block');
    var store = new dojo.data.ItemFileWriteStore(
        {data:jub.toStoreData(lineitems, null, 
            {virtualFields:['estimated_price', 'actual_price']})});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    JUBGrid.populate(liGrid, model, lineitems);
}




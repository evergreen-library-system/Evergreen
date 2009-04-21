dojo.require('dijit.form.Form');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');


function getPOOwner(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, 'owner');
    return new openils.User({id:data}).user.usrname();
}

function doSearch(fields) {
    
    if(isNaN(fields.id)) {
        delete fields.id;
        for(var k in fields) {
            if(fields[k] == '' || fields[k] == null)
                delete fields[k];
        }
    } else {
        // ID search trumps other searches
        fields = {id:fields.id};
    }

    // no search fields
    var some = false;
    for(var k in fields) some = true;
    if(!some) fields.id = {'!=' : null};

    poGrid.resetStore();
    poGrid.loadAll({order_by:{acqpo : 'edit_time DESC'}, limit: 30}, fields);
}

function loadForm() {

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo', 
        fmField : 'provider', 
        parentNode : dojo.byId('po-search-provider-selector'),
        orgLimitPerms : ['VIEW_PURCHASE_ORDER'],
        dijitArgs : {name:'provider', required:false}
    }).build();

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo', 
        fmField : 'ordering_agency', 
        parentNode : dojo.byId('po-search-agency-selector'),
        orgLimitPerms : ['VIEW_PURCHASE_ORDER'],
        dijitArgs : {name:'ordering_agency', required:false}
    }).build();

    doSearch({ordering_agency : openils.User.user.ws_ou()});
}

openils.Util.addOnLoad(loadForm);

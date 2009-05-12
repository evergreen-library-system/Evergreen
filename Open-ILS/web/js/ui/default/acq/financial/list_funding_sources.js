dojo.require("dijit.Dialog");
dojo.require("dijit.form.FilteringSelect");
dojo.require('openils.acq.FundingSource');
dojo.require('openils.acq.CurrencyType');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.grid.DataGrid');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.widget.AutoGrid');

function getOrgInfo(rowIndex, item) {
    if(!item) return ''; 
    var owner = this.grid.store.getValue(item, 'owner'); 
    return fieldmapper.aou.findOrgUnit(owner).shortname();

}

function getBalanceInfo(rowIndex, item) {
    if(!item) return '';
    var id = this.grid.store.getValue( item, 'id');   
    var fs = openils.acq.FundingSource.cache[id];
    if(fs && fs.summary())
        return fs.summary().balance;
    return 0;
}

function loadFSGrid() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.funding_source.org.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, null, {flesh_summary:1}],
                onresponse : function(r) { /* request object*/ 
                if(fs = openils.Util.readResponse(r)) {
                    openils.acq.FundingSource.cache[fs.id()] = fs;
                    fsGrid.store.newItem(acqfs.toStoreItem(fs));
                }
            }
        }
    );
}

openils.Util.addOnLoad(loadFSGrid);


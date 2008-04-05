if(!dojo._hasResource['openils.acq.FundingSource']) {
dojo._hasResource['openils.acq.FundingSource'] = true;
dojo.provide('openils.acq.FundingSource');

/** Declare the FundingSource class with dojo */
dojo.declare('openils.acq.FundingSource', null, {
    /* add instance methods here if necessary */
});

/* define some static methods ------- */

openils.acq.FundingSource.createFundingSourceGrid = function(domId, structure) {
    /** Fetches the list of funding_sources and builds a grid from them */
    openils.acq.FundingSource.fetchList(
        function(srcs) {
            items = [];
            for(var f in srcs) {
                var src = srcs[f];
                items.push({
                    id:src.id(),
                    name:src.name(), 
                    owner: findOrgUnit(src.owner()).name(),
                    currency_type:src.currency_type(),
                    balance:src.summary()['balance']
                });
            }
            openils.acq.FundingSource.buildGrid(domId, structure, items);
        }
    );
}

openils.acq.FundingSource.fetchList = function(callback) {
    /** Retrieves the list of fund objects that I have permission to view */
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1}); /* XXX make this a streaming call */
    req.oncomplete = function(r) {
        callback(r.recv().content());
    };
    req.send();
};

openils.acq.FundingSource.buildGrid = function(domId, structure, dataList, identifier) {
    /** Builds a dojo grid based on the provided data.  
     * @param domId The DOM node where the grid lives 
     * @param structure The layout of the grid. i.e. colums.
     * @param dataList List of objects (hashes) to be inserted into the grid.
     * @paramd identifier The ID field for objects in the grid.  Defaults to 'id'
     */
    identifier = (identifier) ? identifier : 'id';
    var store = new dojo.data.ItemFileWriteStore({data:{identifier:identifier,items:dataList}});
    var model = new dojox.grid.data.DojoData(null, store, {rowsPerPage: 20, clientSort: true});
    var grid = new dojox.Grid({structure: structure, model: model}, dojo.byId(domId));
    grid.setModel(model);
    grid.setStructure(structure);
    grid.startup();
    return {grid:grid, store:store, model:model};
};
}


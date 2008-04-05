if(!dojo._hasResource['openils.acq.Fund']) {
dojo._hasResource['openils.acq.Fund'] = true;
dojo.provide('openils.acq.Fund');

/** Declare the Fund class with dojo */
dojo.declare('openils.acq.Fund', null, {
    /* add instance methods here if necessary */
});

/* define some static fund methods ------- */

openils.acq.Fund.createFundGrid = function(domId, structure) {
    /** Fetches the list of funds and builds a grid from them */
    openils.acq.Fund.fetchList(
        function(funds) {
            items = [];
            for(var f in funds) {
                var fund = funds[f];
                items.push({
                    id:fund.id(),
                    name:fund.name(), 
                    org: findOrgUnit(fund.org()).name(),
                    currency_type:fund.currency_type(),
                    year:fund.year(),
                    combined_balance:fund.summary()['combined_balance']
                });
            }
            openils.acq.Fund.buildGrid(domId, structure, items);
        }
    );
}

openils.acq.Fund.fetchList = function(callback) {
    /** Retrieves the list of fund objects that I have permission to view */
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.fund.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1}); /* XXX make this a streaming call */
    req.oncomplete = function(r) {
        callback(r.recv().content());
    };
    req.send();
};

openils.acq.Fund.buildGrid = function(domId, structure, dataList, identifier) {
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


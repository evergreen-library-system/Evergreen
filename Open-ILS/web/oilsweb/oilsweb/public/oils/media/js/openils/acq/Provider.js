if(!dojo._hasResource['openils.acq.Provider']) {
dojo._hasResource['openils.acq.Provider'] = true;
dojo.provide('openils.acq.Provider');

/** Declare the Provider class with dojo */
dojo.declare('openils.acq.Provider', null, {
    /* add instance methods here if necessary */
});

/* define some static provider methods ------- */

openils.acq.Provider.createProviderGrid = function(domId, structure) {
    /** Fetches the list of providers and builds a grid from them */
    openils.acq.Provider.fetchList(
        function(providers) {
            items = [];
            for(var p in providers) {
                var prov = providers[p];
                items.push({
                    id:prov.id(),
                    name:prov.name(), 
                    owner: findOrgUnit(prov.owner()).name(),
                    currency_type:prov.currency_type()
                });
            }
            openils.acq.Provider.buildGrid(domId, structure, items);
        }
    );
}

openils.acq.Provider.fetchList = function(callback) {
    /** Retrieves the list of provider objects that I have permission to view */
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.provider.org.retrieve', oilsAuthtoken); /* XXX make this a streaming call */
    req.oncomplete = function(r) {
        callback(r.recv().content());
    };
    req.send();
};

openils.acq.Provider.buildGrid = function(domId, structure, dataList, identifier) {
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


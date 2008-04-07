if(!dojo._hasResource['openils.acq.Provider']) {
dojo._hasResource['openils.acq.Provider'] = true;
dojo.provide('openils.acq.Provider');
dojo.require('util.Dojo');

/** Declare the Provider class with dojo */
dojo.declare('openils.acq.Provider', null, {
    /* add instance methods here if necessary */
});

/* define some static provider methods ------- */

openils.acq.Provider.loadGrid = function(domId, columns) {
    /** Fetches the list of providers and builds a grid from them */

    var gridRefs = util.Dojo.buildSimpleGrid(domId, columns, [], 'id', true);
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.provider.org.retrieve', oilsAuthtoken);

    req.oncomplete = function(r) {
        var msg
        gridRefs.grid.setModel(gridRefs.model);
        while(msg = r.recv()) {
            var prov = msg.content();
            gridRefs.store.newItem({
                id:prov.id(),
                name:prov.name(), 
                owner: findOrgUnit(prov.owner()).name(),
                currency_type:prov.currency_type()
            });
        }
        gridRefs.grid.update();
    };

    req.send();
    return gridRefs.grid;
};
}


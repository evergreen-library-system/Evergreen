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

    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.provider.org.retrieve', oilsAuthtoken); /* XXX make this a streaming call */

    req.oncomplete = function(r) {
        var providers = r.recv().content();
        var items = [];

        for(var p in providers) {
            var prov = providers[p];
            items.push({
                id:prov.id(),
                name:prov.name(), 
                owner: findOrgUnit(prov.owner()).name(),
                currency_type:prov.currency_type()
            });
        }
        util.Dojo.buildSimpleGrid(domId, columns, items);
    };
    req.send();
};
}


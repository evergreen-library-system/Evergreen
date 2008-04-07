if(!dojo._hasResource['openils.acq.FundingSource']) {
dojo._hasResource['openils.acq.FundingSource'] = true;
dojo.provide('openils.acq.FundingSource');
dojo.require('util.Dojo');

/** Declare the FundingSource class with dojo */
dojo.declare('openils.acq.FundingSource', null, {
    /* add instance methods here if necessary */
});

//openils.acq.FundingSource.loadGrid = function(domId, columns, gridBuiltHandler) {
openils.acq.FundingSource.loadGrid = function(domId, columns) {
    /** Fetches the list of funding_sources and builds a grid from them */

    var gridRefs = util.Dojo.buildSimpleGrid(domId, columns, [], 'id', true);
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1}); /* XXX make this a streaming call */

    req.oncomplete = function(r) {
        srcs = r.recv().content();

        for(var f in srcs) {
            var src = srcs[f];
            gridRefs.store.newItem({
                id:src.id(),
                name:src.name(), 
                owner: findOrgUnit(src.owner()).name(),
                currency_type:src.currency_type(),
                balance:src.summary()['balance']
            });
        }

        /* set the model after loading all of the data */
        gridRefs.grid.setModel(gridRefs.model);
    };
    req.send();
    //return gridRefs;
    return gridRefs.grid;
};
}


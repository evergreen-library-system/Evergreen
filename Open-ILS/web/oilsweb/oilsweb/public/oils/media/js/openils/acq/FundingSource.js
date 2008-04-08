if(!dojo._hasResource['openils.acq.FundingSource']) {
dojo._hasResource['openils.acq.FundingSource'] = true;
dojo.provide('openils.acq.FundingSource');
dojo.require('util.Dojo');

/** Declare the FundingSource class with dojo */
dojo.declare('openils.acq.FundingSource', null, {
    /* add instance methods here if necessary */
});

openils.acq.FundingSource.cache = {};

//openils.acq.FundingSource.loadGrid = function(domId, columns, gridBuiltHandler) {
openils.acq.FundingSource.loadGrid = function(domId, columns) {
    /** Fetches the list of funding_sources and builds a grid from them */

    var gridRefs = util.Dojo.buildSimpleGrid(domId, columns, [], 'id', true);
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1});

    req.oncomplete = function(r) {
        var msg
        gridRefs.grid.setModel(gridRefs.model);
        while(msg = r.recv()) {
            var src = msg.content();
            openils.acq.FundingSource.cache[src.id()] = src;
            gridRefs.store.newItem({
                id:src.id(),
                name:src.name(), 
                owner: findOrgUnit(src.owner()).name(),
                currency_type:src.currency_type(),
                balance:new String(src.summary()['balance'])
            });
        }
        gridRefs.grid.update();
    };

    req.send();
    return gridRefs.grid;
};


openils.acq.FundingSource.loadGrid = function(grid, model) {
    /** Fetches the list of funding_sources and builds a grid from them */
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1});

    req.oncomplete = function(r) {
        var msg
        grid.setModel(model);
        while(msg = r.recv()) {
            var src = msg.content();
            openils.acq.FundingSource.cache[src.id()] = src;
            model.store.newItem({
                id:src.id(),
                name:src.name(), 
                owner: findOrgUnit(src.owner()).name(),
                currency_type:src.currency_type(),
                balance:new String(src.summary()['balance'])
            });
        }
        grid.update();
    };

    req.send();
};



/**
 * Create a new funding source object
 * @param fields Key/value pairs used to create the new funding source
 */
openils.acq.FundingSource.create = function(fields, onCreateComplete) {

    var fs = new acqfs()
    for(var field in fields) 
        fs[field](fields[field]);

    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.create', oilsAuthtoken, fs);

    req.oncomplete = function(r) {
        var msg = r.recv();
        var id = msg.content();
        fs.id(id); /* XXX check for event */
        if(onCreateComplete)
            onCreateComplete(fs);
    };
    req.send();
};


openils.acq.FundingSource.deleteFromGrid = function(grid, onComplete) {
    var list = []
    var selected = grid.selection.getSelected();
    for(var rowIdx in selected) 
        list.push(grid.model.getDatum(selected[rowIdx], 0));
    openils.acq.FundingSource.deleteList(list, onComplete);
};

openils.acq.FundingSource.deleteList = function(list, onComplete) {
    openils.acq.FundingSource._deleteList(list, 0, onComplete);
}

openils.acq.FundingSource._deleteList = function(list, idx, onComplete) {
    if(idx >= list.length)    
        return onComplete();
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.delete', oilsAuthtoken, list[idx]);
    req.oncomplete = function(r) {
        msg = r.recv()
        stat = msg.content();
        /* XXX CHECH FOR EVENT */
        openils.acq.FundingSource._deleteList(list, ++idx, onComplete);
    }
    req.send();
};


} /* end dojo._hasResource[] */

/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource['openils.acq.FundingSource']) {
dojo._hasResource['openils.acq.FundingSource'] = true;
dojo.provide('openils.acq.FundingSource');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.dojoData');

/** Declare the FundingSource class with dojo */
dojo.declare('openils.acq.FundingSource', null, {
    /* add instance methods here if necessary */
});

/** cached funding_source objects */
openils.acq.FundingSource.cache = {};

openils.acq.FundingSource.createStore = function(onComplete) {
    /** Fetches the list of funding_sources and builds a grid from them */
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.funding_source.org.retrieve', 
        openils.User.authtoken, null, {flesh_summary:1});

    req.oncomplete = function(r) {
        var msg
        var items = [];
        var src = null;
        while(msg = r.recv()) {
            src = msg.content();
            openils.acq.FundingSource.cache[src.id()] = src;
            items.push(src);
        }
        onComplete(acqfs.toStoreData(items));
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
    var req = ses.request('open-ils.acq.funding_source.create', openils.User.authtoken, fs);

    req.oncomplete = function(r) {
        var msg = r.recv();
        var id = msg.content();
        if(onCreateComplete)
            onCreateComplete(id);
    };
    req.send();
};

/**
 * Synchronous funding_source retrievel method 
 */
openils.acq.FundingSource.retrieve = function(id) {
    if(openils.acq.FundingSource.cache[id])
        return openils.acq.FundingSource.cache[id];
    openils.acq.FundingSource.cache[id] = fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.funding_source.retrieve'],
        [openils.User.authtoken, id]
    );
    return openils.acq.FundingSource.cache[id];
};


openils.acq.FundingSource.createCredit = function(fields, onCreateComplete) {

    var fsc = new acqfscred()
    for(var field in fields) 
        fsc[field](fields[field]);

    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request(
        'open-ils.acq.funding_source_credit.create', openils.User.authtoken, fsc);

    req.oncomplete = function(r) {
        var msg = r.recv();
        var id = msg.content();
        if(onCreateComplete)
            onCreateComplete(id);
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
    var req = ses.request('open-ils.acq.funding_source.delete', openils.User.authtoken, list[idx]);
    delete openils.acq.FundingSource.cache[list[idx]];

    req.oncomplete = function(r) {
        msg = r.recv()
        stat = msg.content();
        /* XXX CHECH FOR EVENT */
        openils.acq.FundingSource._deleteList(list, ++idx, onComplete);
    }
    req.send();
};


} /* end dojo._hasResource[] */

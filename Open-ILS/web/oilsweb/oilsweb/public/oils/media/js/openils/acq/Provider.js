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
    var req = ses.request('open-ils.acq.provider.org.retrieve', openils.User.authtoken);

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


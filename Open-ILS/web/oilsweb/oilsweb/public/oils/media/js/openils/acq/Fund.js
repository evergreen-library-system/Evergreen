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

if(!dojo._hasResource['openils.acq.Fund']) {
dojo._hasResource['openils.acq.Fund'] = true;
dojo.provide('openils.acq.Fund');
dojo.require('util.Dojo');

/** Declare the Fund class with dojo */
dojo.declare('openils.acq.Fund', null, {
    /* add instance methods here if necessary */
});


openils.acq.Fund.loadGrid = function(domId, columns) {
    /** Fetches the list of funds and builds a grid from them */

    var gridRefs = util.Dojo.buildSimpleGrid(domId, columns, [], 'id', true);
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.fund.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1});

    req.oncomplete = function(r) {
        var msg
        gridRefs.grid.setModel(gridRefs.model);
        while(msg = r.recv()) {
            var fund = msg.content();
            gridRefs.store.newItem({
                id:fund.id(),
                name:fund.name(), 
                org: findOrgUnit(fund.org()).name(),
                currency_type:fund.currency_type(),
                year:fund.year(),
                combined_balance:fund.summary()['combined_balance']
            });
        }
        gridRefs.grid.update();
    };

    req.send();
    return gridRefs.grid;
};
}


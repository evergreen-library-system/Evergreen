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

if(!dojo._hasResource["openils.acq.CurrencyType"]) {

    dojo._hasResource["openils.acq.CurrencyType"] = true;
    dojo.provide("openils.acq.CurrencyType");
    dojo.require('openils.User');
    dojo.require('openils.Util');
    dojo.require('openils.PermaCrud');

    dojo.declare('openils.acq.CurrencyType', null, {
    });

    openils.acq.CurrencyType.cache = {};

    /**
     * Retrieves all of the currency types
     */
    openils.acq.CurrencyType.fetchAll = function(onComplete) {
        var list = [];
        var pcrud = new openils.PermaCrud();
        pcrud.retrieveAll('acqct', {
            async : true,
            oncomplete : function(r) {
                var types = openils.Util.readResponse(r);
                for(var idx in types)
                    openils.acq.CurrencyType.cache[types[idx].code()] = types[idx];
                onComplete(types);
            }
        });
    };

    openils.acq.CurrencyType.loadSelectWidget = function(selector) {
        openils.acq.CurrencyType.fetchAll(
            function(ctypes) {
                selector.store = new dojo.data.ItemFileReadStore(
                    {data:acqct.toStoreData(ctypes, 'code', {identifier:'code'})});
                selector.setValue(ctypes[0].code()); /* XXX get from setting */
            }
        );
    };
}


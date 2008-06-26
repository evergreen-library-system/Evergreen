/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Author: Bill Erickson <erickson@esilibrary.com>
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

if(!dojo._hasResource["openils.CopyLocation"]) {

    dojo._hasResource["openils.CopyLocation"] = true;
    dojo.provide("openils.CopyLocation");
    dojo.declare('openils.CopyLocation', null, {
    });

    openils.CopyLocation.cache = {};
    openils.CopyLocation.storeCache = {};

    openils.CopyLocation.createStore = function(focusOrg, onload, nocache) {
        if(!nocache && openils.CopyLocation.storeCache[focusOrg])
            return onload(openils.CopyLocation.storeCache[focusOrg]);
        function mkStore(r) {
            var locs = r.recv().content();
            for(var i = 0; i < locs.length; i++) 
                openils.CopyLocation.cache[locs[i].id()] = locs[i];
            openils.CopyLocation.storeCache[focusOrg] = acpl.toStoreData(locs);
            onload(openils.CopyLocation.storeCache[focusOrg]);
        }
        fieldmapper.standardRequest(
            ['open-ils.circ', 'open-ils.circ.copy_location.retrieve.all'],
            {   async: true,
                params: [focusOrg],
                oncomplete: mkStore
            }
        );
    }

    openils.CopyLocation.retrieve = function(id) {
        if(openils.CopyLocation.cache[id])
            return openils.CopyLocation.cache[id];
        return openils.CopyLocation.cache[id] = 
            fieldmapper.standardRequest(
                ['open-ils.circ', 'open-ils.circ.copy_location.retrieve'], [id]);
    }
}


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
if(!dojo._hasResource['openils.acq.LineitemAttr']) {
dojo._hasResource['openils.acq.LineitemAttr'] = true;
dojo.provide('openils.acq.LineitemAttr');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.User');
dojo.require('openils.Event');

/** Declare the LineitemAttr class with dojo */
dojo.declare('openils.acq.LineitemAttr', null, {});

/** Pile of static methods for handling the different types of 
 * lineitem attributes and definitions
 */


/**
 * Creates a set of attr definition stores, one per definition type.
 */
openils.acq.LineitemAttr.createAttrDefStores = function(onload) {
    function process(r) {
        var res = r.recv().content();
        openils.Event.parse_and_raise(res);
        var stores = {};
        stores.marc = acqlimad.toStoreData(res.marc);
        stores.usr = acqliuad.toStoreData(res.usr);
        stores.local = acqlilad.toStoreData(res.local);
        stores.generated = acqligad.toStoreData(res.generated);
        stores.provider = acqlipad.toStoreData(res.provider);
        onload(stores);
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem_attr_definition.retrieve.all'],
        {   async: true,
            params: [openils.User.authtoken],
            oncomplete: process
        }
    );
}
}

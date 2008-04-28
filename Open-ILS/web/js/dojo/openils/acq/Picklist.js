/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * David J. Fiander <david@fiander.info>
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

if(!dojo._hasResource['openils.acq.Picklist']) {
dojo._hasResource['openils.acq.Picklist'] = true;
dojo.provide('openils.acq.Picklist');

dojo.require('fieldmapper.Fieldmapper');

/** Declare the Picklist class with dojo */
dojo.declare('openils.acq.Picklist', null, {
    /* add instance methods here if necessary */
});

openils.acq.Picklist.cache = {};

openils.acq.Picklist.createStore = function(pl_id, onComplete) {
    // Fetches the list of titles in a picklist and builds a grid

    function mkStore(r) {
	var msg;
	var items = [];
	while (msg = r.recv()) {
	    var data = msg.content();
	    openils.acq.Picklist.cache[data.id()] = data;

	    items.push(data);
	}
	onComplete(jub.toStoreData(items));
    }

    fieldmapper.standardRequest(
	['open-ils.acq', 'open-ils.acq.lineitem.picklist.retrieve'],
	{ async: true,
	  params: [openils.User.authtoken, pl_id, {flesh_attrs:1}],
	  oncomplete: mkStore
	});
};

openils.acq.Picklist.find_attr = function(id, at_name, at_type) {
    var li = openils.acq.Picklist.cache[id];
    for (var i in li.attributes()) {
	var attr = li.attributes()[i];
	if (attr.attr_type() == at_type && attr.attr_name() == at_name) {
	    return attr.attr_value();
	}
    }
    return '';
};

openils.acq.Picklist.onRowClick = function(evt) {
    var gridRefs = openils.acq.Picklist._gridRefs;
    var row = gridRefs.grid.model.getRow(evt.rowIndex);

    openils.acq.Lineitems.loadGrid('oils-acq-picklist-details-grid', row.id);
};
}


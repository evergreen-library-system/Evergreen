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

dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.grid.Grid');
dojo.require('dojox.grid._data.model');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.dojoData');

/** Declare the Picklist class with dojo */
dojo.declare('openils.acq.Picklist', null, {
    constructor: function (pl_id, onComplete, args) {
	var pl_this = this;		// 'this' doesn't exist inside callbacks
    var liArgs = (args && args.liArgs) ? args.liArgs : {flesh_attrs:1, clear_marc:1};
	var mkStore = function (r) {
	    var storeData;
	    var msg;
	    pl_this._items = [];

	    while (msg = r.recv()) {
		var data = msg.content();
		pl_this._data[data.id()] = data;
		pl_this._items.push(data);
	    }

	    storeData = jub.toStoreData(pl_this._items);
	    pl_this._store = new dojo.data.ItemFileWriteStore({data:storeData});
	    pl_this._model = new dojox.grid.data.DojoData(null, pl_this._store,
						       {rowsPerPage:20, clientSort:true,
							query:{id:'*'}});
	    onComplete(pl_this._model);
	};

	this._id = pl_id;
	this._data = {};
	this._plist = null;
	// Fetch the picklist information
	fieldmapper.standardRequest(
	    ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
	    { async: false,
	      params: [openils.User.authtoken, pl_id, {flesh_lineitem_count:1}],
	      oncomplete: function(r) {
		  var msg = r.recv();
		  pl_this._plist = msg.content();
	      }
	    });

	// Fetch the title list for the picklist, asynchronously
	fieldmapper.standardRequest(
	    ['open-ils.acq', 'open-ils.acq.lineitem.picklist.retrieve'],
	    { async: true,
	      params: [openils.User.authtoken, pl_id, liArgs],
	      oncomplete: mkStore
	    });
    },
    id: function () {
	return this._id;
    },
    name: function() {
	return this._plist.name();
    },
    owner: function() {
	return this._plist.owner();
    },
    create_time: function() {
	return this._plist.create_time();
    },
    edit_time: function() {
	return this._plist.edit_time();
    },
    find_attr: function(id, at_name, at_type) {
	attr_list = this._data[id].attributes();
	for (var i in attr_list) {
	    var attr = attr_list[i];
	    if (attr.attr_type() == at_type && attr.attr_name() == at_name) {
		return attr.attr_value();
	    }
	}
	return '';
    },
    onJUBSet: function (griditem, attr, oldVal,newVal) {
	var item;
	var updateDone = function(r) {
	    var stat = r.recv().content();
	    var evt = openils.Event.parse(stat);

	    if (evt) {
		alert("Error: "+evt.desc);
		console.dir(evt);
	    }
	};

	if (oldVal == newVal) {
	    return;
	}

	item = this._data[griditem.id];
	if (attr == "provider") {
        if(newVal == '') 
            newVal = null;
	    item.provider(newVal);
	} else {
	    //alert("Unexpected attr in Picklist.onSet: '"+attr+"'");
	    return;
	}

	fieldmapper.standardRequest(
	    ["open-ils.acq", "open-ils.acq.lineitem.update"],
	    {params: [openils.User.authtoken, item],
	     oncomplete: updateDone
	    });
    },
});

/** Creates a new picklist. fields.name is required */ 
openils.acq.Picklist.create = function(fields, oncomplete) {
    var picklist = new acqpl();
    picklist.owner(fields.owner || new openils.User().user.id());
    picklist.name(fields.name);

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.create'],
        {   async: true,
            params: [openils.User.authtoken, picklist],
            oncomplete: function(r) { 
                // XXX event/error handling
                oncomplete(r.recv().content());
            }
        }
    );
}

/** Creates a new picklist. fields.name is required */ 
openils.acq.Picklist.update = function(picklist, oncomplete) {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.update'],
        {   async: true,
            params: [openils.User.authtoken, picklist],
            oncomplete: function(r) { 
                // XXX event/error handling
                oncomplete(r.recv().content());
            }
        }
    );
}

/** Deletes a list of picklists
 * @param list Array of picklist IDs
 */
openils.acq.Picklist.deleteList = function(list, onComplete) {
    openils.acq.Picklist._deleteList(list, 0, onComplete);
}

/* iterate through the list of IDs deleting asynchronously as we go... */
openils.acq.Picklist._deleteList = function(list, idx, onComplete) {
    if(idx >= list.length)
        return onComplete();
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.delete'],
        {   async: true,
            params: [openils.User.authtoken, list[idx]],
            oncomplete: function(r) {
                msg = r.recv()
                stat = msg.content();
                /* XXX CHECH FOR EVENT */
                openils.acq.Picklist._deleteList(list, ++idx, onComplete);
            }
        }
    );
}

}


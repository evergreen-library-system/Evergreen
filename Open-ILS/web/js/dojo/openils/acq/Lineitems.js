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

if(!dojo._hasResource['openils.acq.Lineitems']) {
dojo._hasResource['openils.acq.Lineitems'] = true;
dojo.provide('openils.acq.Lineitems');

dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.grid.Grid');
dojo.require('dojox.grid._data.model');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.User');

/** Declare the Lineitems class with dojo */
dojo.declare('openils.acq.Lineitems', null, {
    /* add instance methods here if necessary */

    constructor: function(args) {
        this.lineitem = args.lineitem;
    },

    findAttr: function(name, type) {
        var attrs = this.lineitem.attributes();
        if(!attrs) return null;
        for(var i = 0; i < attrs.length; i++) {
            var attr = attrs[i];
            if (attr.attr_type() == type && attr.attr_name() == name) 
                return attr.attr_value();
        }
    },

    update: function(oncomplete) {
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.update'],
            {   async: true,
                params: [openils.User.authtoken, this.lineitem],
                oncomplete: function(r) {
                    oncomplete(r.recv().content())
                }
            }
        );
    },

    setState: function(newState, oncomplete) {
	this.lineitem.state(newState);
	this.update(oncomplete);
    },
});

openils.acq.Lineitems.ModelCache = {};
openils.acq.Lineitems.acqlidCache = {};

openils.acq.Lineitems.createStore = function(li_id, onComplete) {
    // Fetches the details of a lineitem and builds a grid

    function mkStore(r) {
	var msg;
	var items = [];
	while (msg = r.recv()) {
	    var data = msg.content();
	    for (i in data.lineitem_details()) {
		var lid = data.lineitem_details()[i];
		items.push(lid);
		openils.acq.Lineitems.acqlidCache[lid.id()] = lid;
	    }
	}

	onComplete(acqlid.toStoreData(items));
    }

    fieldmapper.standardRequest(
	['open-ils.acq', 'open-ils.acq.lineitem.retrieve'],
	{ async: true,
	  params: [openils.User.authtoken, li_id,
		   {flesh_attrs:1, flesh_li_details:1}],
	  oncomplete: mkStore
	});
};

openils.acq.Lineitems.alertOnSet = function(griditem, attr, oldVal, newVal) {
    var item;
    var updateDone = function(r) {
	var stat = r.recv().content();
	// XXX Check for Event
    }

    if (oldVal == newVal) {
	return;
    }

    item = openils.acq.Lineitems.acqlidCache[griditem.id];
    
    if (attr == "fund") {
	item.fund(newVal);
    } else if (attr ==  "owning_lib") {
	item.owning_lib(newVal);
    } else if (attr ==  "cn_label") {
	item.cn_label(newVal);
    } else if (attr ==  "barcode") {
	item.barcode(newVal);
    } else if (attr ==  "location") {
	item.location(newVal);
    } else {
	alert("Unexpected attr in Lineitems.alertOnSet: '"+attr+"'");
	return;
    }

    fieldmapper.standardRequest(
	["open-ils.acq", "open-ils.acq.lineitem_detail.update"],
	{ params: [openils.User.authtoken, item],
	  oncomplete: updateDone
	});
};

openils.acq.Lineitems.deleteLID = function(id, onComplete) {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem_detail.delete'],
        {   async: true,
            params: [openils.User.authtoken, id],
            oncomplete: function(r) {
                msg = r.recv()
                stat = msg.content();
		onComplete();
            }
    });
};

openils.acq.Lineitems.createLID = function(fields, onCreateComplete) {
    var lid = new acqlid()
    for (var field in fields) {
	lid[field](fields[field]);
    }

    fieldmapper.standardRequest(
	['open-ils.acq', 'open-ils.acq.lineitem_detail.create'],
	{ async: true,
	  params: [openils.User.authtoken, lid],
	  oncomplete: function(r) {
	      var msg = r.recv();

	      fields.id = msg.content();
	      if (onCreateComplete) {
		  onCreateComplete(fields);
	      }
	  }
	});
};

openils.acq.Lineitems.loadGrid = function(domNode, id, layout) {
    if (!openils.acq.Lineitems.ModelCache[id]) {
	openils.acq.Lineitems.createStore(id,
		function(storeData) {
		    var store = new dojo.data.ItemFileWriteStore({data:storeData});
		    var model = new dojox.grid.data.DojoData(null, store,
			{rowsPerPage: 20, clientSort:true, query:{id:'*'}});

		    dojo.connect(store, "onSet",
				 openils.acq.Lineitems.alertOnSet);
		    openils.acq.Lineitems.ModelCache[id] = model;

		    domNode.setStructure(layout);
		    domNode.setModel(model);
		    domNode.update();
		});
    } else {
	domNode.setModel(openils.acq.Lineitems.ModelCache[id]);
	domNode.update();
    }
};
}

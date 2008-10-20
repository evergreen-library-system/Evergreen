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

if(!dojo._hasResource['openils.acq.Lineitem']) {
dojo._hasResource['openils.acq.Lineitem'] = true;
dojo.provide('openils.acq.Lineitem');

dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojox.grid.Grid');
dojo.require('dojox.grid._data.model');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.User');
dojo.require('openils.Event');

/** Declare the Lineitem class with dojo */
dojo.declare('openils.acq.Lineitem', null, {
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

    // returns the actual price if available, otherwise estimated price, otherwise null
    // priority is given to local attrs, then provider attrs, then MARC attrs
    getPrice: function() {
        return this.getActualPrice() || this.getEstimatedPrice();
    },

    // returns the actual price, null if none
    getActualPrice : function() {
        return this._getPriceAttr('actual_price');
    },

    // returns the estimated price, null if none
    getEstimatedPrice : function() {
        return this._getPriceAttr('estimated_price');
    },

    _getPriceAttr : function(attr) {
        var types = [
            'lineitem_local_attr_definition', 
            'lineitem_provider_attr_definition', 
            'lineitem_marc_attr_definition'
        ];

        for(var t in types) {
            if(price = this.findAttr(attr, types[t]))
                return {price:price, source_type: attr, source_attr: types[t]};
        }

        return null;
    },

    update: function(oncomplete) {
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.update'],
            {   async: true,
                params: [openils.User.authtoken, this.lineitem],
                oncomplete: function(r) {
		    oncomplete(openils.Event.parse(r.recv().content()));
                }
            }
        );
    },

    approve: function(oncomplete) {
	fieldmapper.standardRequest(
	    ['open-ils.acq', 'open-ils.acq.lineitem.approve'],
	    {  async: true,
	       params: [openils.User.authtoken, this.lineitem.id()],
	       oncomplete: function(r) {
		   oncomplete(openils.Event.parse(r.recv().content()));
	       }
	    });
    },

    id: function() {
	return this.lineitem.id();
    },
});

openils.acq.Lineitem.ModelCache = {};
openils.acq.Lineitem.acqlidCache = {};

openils.acq.Lineitem.createLIDStore = function(li_id, onComplete) {
    // Fetches the details of a lineitem and builds a grid

    function mkStore(r) {
	var msg;
	var items = [];
	while (msg = r.recv()) {
	    var data = msg.content();
	    for (i in data.lineitem_details()) {
		var lid = data.lineitem_details()[i];
		items.push(lid);
		openils.acq.Lineitem.acqlidCache[lid.id()] = lid;
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

openils.acq.Lineitem.alertOnLIDSet = function(griditem, attr, oldVal, newVal) {
    var item;
    var updateDone = function(r) {
	var stat = r.recv().content();
	var evt = openils.Event.parse(stat);

	if (evt) {
	    alert("Error: "+evt.desc);
	    console.dir(evt);
	    if (attr == "fund") {
		item.fund(oldVal);
		griditem.fund = oldVal;
	    } else if (attr ==  "owning_lib") {
		item.owning_lib(oldVal);
		griditem.owning_lib = oldVal;
	    }
	}
    };

    if (oldVal == newVal) {
	return;
    }

    item = openils.acq.Lineitem.acqlidCache[griditem.id];
    
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
	alert("Unexpected attr in Lineitem.alertOnSet: '"+attr+"'");
	return;
    }

    fieldmapper.standardRequest(
	["open-ils.acq", "open-ils.acq.lineitem_detail.update"],
	{ params: [openils.User.authtoken, item],
	  oncomplete: updateDone
	});
};

openils.acq.Lineitem.deleteLID = function(id, onComplete) {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem_detail.delete'],
        {   async: true,
            params: [openils.User.authtoken, id],
            oncomplete: function(r) {
                msg = r.recv()
                stat = msg.content();
		onComplete(openils.Event.parse(stat));
            }
    });
};

openils.acq.Lineitem.createLID = function(fields, onCreateComplete) {
    var lid = new acqlid()
    for (var field in fields) {
	lid[field](fields[field]);
    }

    fieldmapper.standardRequest(
	['open-ils.acq', 'open-ils.acq.lineitem_detail.create'],
	{ async: true,
	  params: [openils.User.authtoken, lid, {return_obj:1}],
	  oncomplete: function(r) {
	      var msg = r.recv();
          var obj = msg.content();
          openils.Event.parse_and_raise(obj);
	      if (onCreateComplete) {
		    onCreateComplete(obj);
	      }
	  }
	});
};

openils.acq.Lineitem.loadLIDGrid = function(domNode, id, layout) {
    if (!openils.acq.Lineitem.ModelCache[id]) {
	openils.acq.Lineitem.createLIDStore(id,
		function(storeData) {
		    var store = new dojo.data.ItemFileWriteStore({data:storeData});
		    var model = new dojox.grid.data.DojoData(null, store,
			{rowsPerPage: 20, clientSort:true, query:{id:'*'}});

		    dojo.connect(store, "onSet",
				 openils.acq.Lineitem.alertOnLIDSet);
		    openils.acq.Lineitem.ModelCache[id] = model;

		    domNode.setStructure(layout);
		    domNode.setModel(model);
		    domNode.update();
		});
    } else {
	domNode.setModel(openils.acq.Lineitem.ModelCache[id]);
	domNode.setStructure(layout);
	domNode.update();
	domNode.refresh();
    }
};
}

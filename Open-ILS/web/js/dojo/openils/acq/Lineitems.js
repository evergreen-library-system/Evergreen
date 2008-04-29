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

/** Declare the Lineitems class with dojo */
dojo.declare('openils.acq.Lineitems', null, {
    /* add instance methods here if necessary */
});

openils.acq.Lineitems.cache = {};

openils.acq.Lineitems.createStore = function(li_id, onComplete) {
    // Fetches the details of a lineitem and builds a grid

    function mkStore(r) {
	var msg;
	var items = [];
	while (msg = r.recv()) {
	    var data = msg.content();
	    alert(js2JSON(data));
	    for (i in data.lineitem_details()) {
		items.push(data.lineitem_details()[i]);
	    }
	}
	openils.acq.Lineitems.cache[li_id] = items;

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

openils.acq.Lineitems.loadGrid = function(domNode, id, layout) {
    if (!openils.acq.Lineitems.cache[id]) {
	openils.acq.Lineitems.createStore(id,
		function(storeData) {
		    var store = new dojo.data.ItemFileReadStore({data:storeData});
		    var model = new dojox.grid.data.DojoData(null, store,
			{rowsPerPage: 20, clientSort:true, query:{id:'*'}});
		    openils.acq.Lineitems.cache[id] = model;

		    domNode.setStructure(layout);
		    domNode.setModel(model);
		    domNode.update();
		    alert('ouch! update');
		});
    } else {
	domNode.setModel(openils.acq.Lineitems.cache[id]);
	domNode.update();
    }
}

// openils.acq.Lineitems.initGrid = function(domId, columns) {
//     var store = new dojo.data.ItemFileWriteStore({data:{identify:'id'}});
//     var model = new dojox.grid.data.DojoData(null, store,
// 	{rowsPerPage: 20, clientSort: true});
    
//     var domNode = dojo.byId(domId);
//     var columns = layout.cells;
//     var colWidth = (dojo.coords(domNode.parentNode).w / columns.length) - 30;
//     for(var i in columns) {
//         if(columns[i].width == undefined)
//             columns[i].width = colWidth + 'px';
//     }


//     var grid = new dojox.Grid({structure: layout}, domId);

//     openils.acq.Lineitems.loadGrid = function(domId, li_id) {
// 	var ses = new OpenSRF.ClientSession('open-ils.acq');
// 	var req = ses.request('open-ils.acq.lineitem.retrieve',
// 	    openils.User.authtoken, li_id, {flesh_attrs:1,flesh_li_details:1});

// 	req.oncomplete = function(r) {
// 	    var msg;
// 	    grid.setModel(gridRefs.model);
// 	    model.query = {id:'*'};

// 	    while (msg = r.recv()) {
// 		var li = msg.content();
		
// 		for (i in li.lineitem_details()) {
// 		    lid = li.lineitem_details()[i]

// 		    alert(js2JSON(lid));

// 		    store.newItem({
// 			id:lid.id(),
// 			fund:lid.fund(),
// 			location:lid.location(),
// 		    });
// 		}
// 	    }
// 	    grid.update();
// 	};

// 	req.send();
//     };

//     return grid;
// };

}

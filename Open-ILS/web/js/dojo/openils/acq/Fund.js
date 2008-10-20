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
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.Event');

/** Declare the Fund class with dojo */
dojo.declare('openils.acq.Fund', null, {
    /* add instance methods here if necessary */
});

openils.acq.Fund.cache = {};
openils.acq.Fund._cachecomplete = false;

openils.acq.Fund.createStore = function(onComplete, limitPerm) {
    /** Fetches the list of funds and builds a grid from them */

    function mkStore(r) {
        var msg;
        var items = [];
        while(msg = r.recv()) {
            var src = msg.content();
            if(e = openils.Event.parse(src))
                return alert(e);
            openils.acq.Fund.cache[src.id()] = src;
            items.push(src);
        }
	    openils.acq.Fund._cachecomplete = true;
        onComplete(acqf.toStoreData(items));
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, null, {flesh_summary:1, limit_perm:limitPerm}],
            oncomplete: mkStore
        }
    );
};

/**
 * Create a new fund
 * @param fields Key/value pairs used to create the new fund
 */
openils.acq.Fund.create = function(fields, onCreateComplete) {

    var fund = new acqf()
    for(var field in fields) 
        fund[field](fields[field]);

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.create'],
        {   async: true,
            params: [openils.User.authtoken, fund],
            oncomplete: function(r) {
                var msg = r.recv();
                var id = msg.content();
                if(onCreateComplete)
                    onCreateComplete(id);
            }
        }
    );
};


openils.acq.Fund.createAllocation = function(fields, onCreateComplete) {
    var alloc = new acqfa()
    for(var field in fields) 
        alloc[field](fields[field]);
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund_allocation.create'],
        {
            async: true,
            params: [openils.User.authtoken, alloc],
            oncomplete: function(r) {
                var msg = r.recv();
                var id = msg.content();
                if(onCreateComplete)
                    onCreateComplete(id);
            }
        }
    );
};


/**
 * Synchronous fund retrievel method 
 */
openils.acq.Fund.retrieve = function(id) {
    if(openils.acq.Fund.cache[id])
        return openils.acq.Fund.cache[id];
    openils.acq.Fund.cache[id] = fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.retrieve'],
        [openils.User.authtoken, id]
    );
    return openils.acq.Fund.cache[id];
};


openils.acq.Fund.deleteFromGrid = function(grid, onComplete) {
    var list = []
    var selected = grid.selection.getSelected();
    for(var rowIdx in selected) 
        list.push(grid.model.getDatum(selected[rowIdx], 0));
    openils.acq.Fund.deleteList(list, onComplete);
};

openils.acq.Fund.deleteList = function(list, onComplete) {
    openils.acq.Fund._deleteList(list, 0, onComplete);
}

openils.acq.Fund._deleteList = function(list, idx, onComplete) {
    if(idx >= list.length)    
        return onComplete();

    var fundId = list[idx];
    delete openils.acq.Fund.cache[list[idx]];

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.delete'],
        {   async: true,
            params: [openils.User.authtoken, fundId],
            oncomplete: function(r) {
                stat = r.recv().content();
                /* XXX CHECH FOR EVENT */
                openils.acq.Fund._deleteList(list, ++idx, onComplete);
            }
        }
    );
};

openils.acq.Fund.nameMapping = function(oncomplete) {
    var ids = [];
    var names = [];
    var buildMap = function() {
	for (var i in openils.acq.Fund.cache) {
	    var item = openils.acq.Fund.cache[i];
	    ids.push(item.id());
	    names.push(item.name());
	    oncomplete(ids, names);
	}
    };

    if (openils.acq.Fund._cachecomplete) {
	buildMap(oncomplete);
    } else {
	openils.acq.Fund.createStore(buildMap);
    }
};

/**
  * Sets the store for an existing openils.widget.FundFilteringSelect 
  * using the funds where the user has the requested permission.
  * @param perm The permission to check
  * @param selector The pre-created dijit.form.FilteringSelect object.  
  */

openils.acq.Fund.storeCache = [];

openils.acq.Fund.buildPermFundSelector = function(perm, selector) {
    dojo.require('dojo.data.ItemFileReadStore');

    function hookupStore(store) {
	selector.store = store;
        selector.startup();
    }

    function buildPicker(r) {
	var msg;
	var fundList = [];
	while (msg = r.recv()) {
	    var fund = msg.content();
	    fundList.push(fund);
	}

	var store = new dojo.data.ItemFileReadStore({data:acqf.toStoreData(fundList)});

	hookupStore(store);
	openils.acq.Fund.storeCache[perm] = store;
    }

    if (openils.acq.Fund.storeCache[perm]) {
	hookupStore(openils.acq.Fund.storeCache[perm]);
    } else {
	fieldmapper.standardRequest(
	    ['open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
            {   params: [openils.User.authtoken, null,
			 {flesh_summary:1, limit_perm:perm}],
		oncomplete: buildPicker,
		async: true
            }
	)
    }
}

}

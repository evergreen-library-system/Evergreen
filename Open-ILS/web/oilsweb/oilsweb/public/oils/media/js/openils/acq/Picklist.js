if(!dojo._hasResource['openils.acq.Picklist']) {
dojo._hasResource['openils.acq.Picklist'] = true;
dojo.provide('openils.acq.Picklist');
dojo.require('util.Dojo');

/** Declare the Picklist class with dojo */
dojo.declare('openils.acq.Picklist', null, {
    /* add instance methods here if necessary */
});

    openils.acq.Picklist.find_attr = function(li, at_name, at_type) {
	for (var i in li.attributes()) {
	    var attr = li.attributes()[i];
	    if (attr.attr_type() == at_type && attr.attr_name() == at_name) {
		return attr.attr_value();
	    }
	}
	return '';
    };


    openils.acq.Picklist.loadGrid = function(domId, columns, pl_id) {
    /** Fetches the list of picklists and builds a grid from them */

    var gridRefs = util.Dojo.buildSimpleGrid(domId, columns, [], 'id', true);
    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.lineitem.picklist.retrieve', 
        openils.User.authtoken, pl_id, {flesh_attrs:1});

    req.oncomplete = function(r) {
        var msg
        gridRefs.grid.setModel(gridRefs.model);
        gridRefs.model.query = {id:'*'};
        while(msg = r.recv()) {
            var jub = msg.content();
	    //alert(js2JSON(jub));
            gridRefs.store.newItem({
		    id:jub.id(),
		    title:openils.acq.Picklist.find_attr(jub, "title", "lineitem_marc_attr_definition"),
		    price:openils.acq.Picklist.find_attr(jub, "price", "lineitem_marc_attr_definition"),
		    provider:jub.provider(),
		    copies:jub.item_count()
		});
        }
        gridRefs.grid.update();
    };

    req.send();
    return gridRefs.grid;
};
}


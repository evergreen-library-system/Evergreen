if(!dojo._hasResource["openils.widget.FundSelector"]){
    dojo._hasResource["openils.widget.FundSelector"] = true;
    dojo.provide("openils.widget.FundSelector");

    dojo.require("dojox.grid.editors");

    /**
     * This widget provides a specific selector for selecting
     * a fund.
     */

    dojo.declare("openils.widget.FundSelector", dojox.grid.editors.Select, {

	constructor: function(inCell) {
	    console.dir(this);
	    this.store = this.store || this.cell.store;
	    this.identifier = this.identifier || this.cell.identifier || "id";
	    this.name = this.name || this.cell.name || "name";
	    this.options = openils.widget.FundSelector.fundNames;
	    this.values = openils.widget.FundSelector.fundCodes;
	}
    });
    
    openils.widget.FundSelector.fundNames = [];
    openils.widget.FundSelector.fundCodes = [];

    fieldmapper.standardRequest(
	['open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
	{
	    async: true,
	    params: [openils.User.authtoken, null, {flesh_summary:1}],
	    oncomplete: function (r) {
		var msg;
		
		while (msg = r.recv()) {
		    var f = msg.content();
		    openils.widget.FundSelector.fundNames.push(f.name());
		    openils.widget.FundSelector.fundCodes.push(f.id());
		}
	    }
	}
    );
}

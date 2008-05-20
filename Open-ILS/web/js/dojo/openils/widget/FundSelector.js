if(!dojo._hasResource["openils.widget.FundSelector"]){
    dojo._hasResource["openils.widget.FundSelector"] = true;
    dojo.provide("openils.widget.FundSelector");

    dojo.require("dojox.grid.editors");

    dojo.require('openils.acq.Fund');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('fieldmapper.dojoData');

    /**
     * This widget provides a specific selector for selecting
     * a fund.
     */

    dojo.declare("openils.widget.FundSelector", dojox.grid.editors.Select, {

	constructor: function(inCell) {
	    this.options = openils.widget.FundSelector.fundNames;
	    this.values = openils.widget.FundSelector.fundCodes;
	}
    });
    
    openils.widget.FundSelector.fundNames = [];
    openils.widget.FundSelector.fundCodes = [];

    dojo.addOnLoad(
	function() {
	    openils.acq.Fund.nameMapping(
		function(ids, names) {
		    openils.widget.FundSelector.fundCodes = ids;
		    openils.widget.FundSelector.fundNames = names;
		});
	});
}

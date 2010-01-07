if(!dojo._hasResource["openils.widget.FundSelector"]){
    dojo._hasResource["openils.widget.FundSelector"] = true;
    dojo.provide("openils.widget.FundSelector");

    dojo.require('openils.acq.Fund');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('fieldmapper.dojoData');

    /**
     * This widget provides a specific selector for selecting
     * a fund.
     */

    dojo.declare(
	"openils.widget.FundSelector", [dijit.form.FilteringSelect],
	{
	});
}

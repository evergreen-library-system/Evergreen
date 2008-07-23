if(!dojo._hasResource["openils.widget.ProviderSelector"]){
    dojo._hasResource["openils.widget.ProviderSelector"] = true;
    dojo.provide("openils.widget.ProviderSelector");

    dojo.require('openils.acq.Provider');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('fieldmapper.dojoData');

    /**
     * This widget provides a specific selector for selecting
     * a provider.
     */

    dojo.declare(
	"openils.widget.ProviderSelector", [dijit.form.FilteringSelect],
	{
	});
}

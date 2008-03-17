if(!dojo._hasResource["dojox.data.tests.module"]){ //_hasResource checks added by build. Do not use _hasResource directly in your code.
dojo._hasResource["dojox.data.tests.module"] = true;
dojo.provide("dojox.data.tests.module");

try{
	dojo.require("dojox.data.tests.stores.CsvStore");
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.stores.HtmlTableStore");
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.stores.OpmlStore");
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.stores.XmlStore");
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.stores.FlickrStore");
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.stores.FlickrRestStore");
	//Load only if in a browser AND if the location is remote (not file.  As it needs a PHP server to work).
	if(dojo.isBrowser){
		if(window.location.protocol !== "file:"){
			dojo.require("dojox.data.tests.stores.QueryReadStore");
		}
	}
	dojo.requireIf(dojo.isBrowser, "dojox.data.tests.dom");
}catch(e){
	doh.debug(e);
}


}

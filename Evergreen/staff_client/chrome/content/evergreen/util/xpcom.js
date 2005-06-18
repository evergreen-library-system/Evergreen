sdump('TRACE','Loading xpcom.js\n');

function xp_url_init(aURL) {
	var URLContractID   = "@mozilla.org/network/standard-url;1";
	var URLIID          = Components.classes[URLContractID].createInstance( );
	var URL             = URLIID.QueryInterface(Components.interfaces.nsIURL);
	if (aURL) {
		URL.spec = aURL;
	}
	return URL;
}

function xp_WebNavigation_init(w) {
	if (!w) { w = this; }
	try {
		var webNavigation = w
			.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
			.getInterface(Components.interfaces.nsIWebNavigation);
		return webNavigation;
	} catch(E) {
	 	sdump('TRACE','WEB NAVIGATION EXCEPTION: ' + js2JSON(e) + '\n');
	}
}


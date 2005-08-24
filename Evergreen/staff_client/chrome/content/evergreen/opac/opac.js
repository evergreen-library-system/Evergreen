sdump('D_OPAC','Loading opac.js\n');

var OPAC_URL = "http://spacely.georgialibraries.org:8080/";
var opac_page_thing;


/* listen for page changes */

function buildProgressListener(p) {
///*
//	var progressListener = 
	return {
	onProgressChange	: function(){},
	onLocationChange	: function(){},
	onStatusChange		: function(){},
	onSecurityChange	: function(){},
	QueryInterface 		: function(){return this;},
	onStateChange 		: function ( webProgress, request, stateFlags, status) {
		const nsIWebProgressListener = Components.interfaces.nsIWebProgressListener;
		const nsIChannel = Components.interfaces.nsIChannel;
		if (stateFlags == 65540 || stateFlags == 65537 || stateFlags == 65552) { return; }
		dump('onStateChange: stateFlags = ' + stateFlags + ' status = ' + status + '\n');
		if (stateFlags & nsIWebProgressListener.STATE_IS_REQUEST) {
			dump('\tSTATE_IS_REQUEST\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_IS_DOCUMENT) {
			dump('\tSTATE_IS_DOCUMENT\n');
			if( stateFlags & nsIWebProgressListener.STATE_STOP ) set_opac_vars(p); 
		}
		if (stateFlags & nsIWebProgressListener.STATE_IS_NETWORK) {
			dump('\tSTATE_IS_NETWORK\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_IS_WINDOW) {
			dump('\tSTATE_IS_WINDOW\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_START) {
			dump('\tSTATE_START\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_REDIRECTING) {
			dump('\tSTATE_REDIRECTING\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_TRANSFERING) {
			dump('\tSTATE_TRANSFERING\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_NEGOTIATING) {
			dump('\tSTATE_NEGOTIATING\n');
		}
		if (stateFlags & nsIWebProgressListener.STATE_STOP) {
			dump('\tSTATE_STOP\n');
		}
	}
}
//*/
	//return progressListener;
}

/* init the opac */
function opac_init(p) {
	sdump('D_OPAC',"Initing OPAC\n");
	opac_page_thing = p;

	p.opac_iframe = p.w.document.getElementById('opac_opac_iframe');
	p.opac_iframe.addProgressListener(buildProgressListener(p), 
		Components.interfaces.nsIWebProgress.NOTIFY_ALL );
	//p.opac_iframe.addProgressListener(progressListener, 
	//	Components.interfaces.nsIWebProgress.NOTIFY_ALL );
	p.opac_iframe.setAttribute("src", OPAC_URL) 
}

/* shoves data into the OPAC's space */
function set_opac_vars(p) {
	if (!p) p = opac_page_thing;
	//var p = opac_page_thing;
	//p.opac_iframe = p.w.document.getElementById('opac_opac_iframe');
	p.opac_iframe.contentWindow.IAMXUL = true;
	p.opac_iframe.contentWindow.xulG = mw.G;
	p.opac_iframe.contentWindow.attachEvt("rresult", "recordDrawn", opac_make_details_page);
}

function opac_make_details_page(id, node) {
	dump("Node HREF attribute is: " + node.getAttribute("href") + "\n and doc id is " + id +'\n');
	alert("Node HREF attribute is: " + node.getAttribute("href") + "\n and doc id is " + id +'\n');
}


/* -------------------------------------------------------------------------- 
	back-forward
 	-------------------------------------------------------------------------- */
function opac_build_navigation(p) {
	p.webForward = function webForward() {
		try {
			if(p.opac_iframe.webNavigation.canGoForward)
				p.opac_iframe.webNavigation.goForward();
		} catch(E) {
			sdump('D_OPAC','goForward error: ' + js2JSON(E) + '\n');
		}
	}

	p.webBack = function webBack() {
		try {
			if(p.opac_iframe.webNavigation.canGoBack)
				p.opac_iframe.webNavigation.goBack();
		} catch(E) {
			sdump('D_OPAC','goBack error: ' + js2JSON(E) + '\n');
		}
	}
}








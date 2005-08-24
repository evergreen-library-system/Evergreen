sdump('D_OPAC','Loading opac.js\n');

var OPAC_URL = "http://spacely.georgialibraries.org:8080/";
var opac_page_thing;


/* listen for page changes */
var progressListener = new Object();
progressListener.onProgressChange	= function(){}
progressListener.onLocationChange	= function(){}
progressListener.onStatusChange		= function(){}
progressListener.onSecurityChange	= function(){}
progressListener.QueryInterface = function qi(iid) { return this; }
progressListener.onStateChange = 
	function client_statechange ( webProgress, request, stateFlags, status) {
		if( stateFlags == 131088 ) set_opac_vars();
};


/* init the opac */
function opac_init(p) {
	sdump('D_OPAC',"Initing OPAC\n");
	opac_page_thing = p;
	p.opac_iframe = p.w.document.getElementById('opac_opac_iframe');
	p.opac_iframe.addProgressListener(progressListener, 
		Components.interfaces.nsIWebProgress.NOTIFY_ALL );
	p.opac_iframe.setAttribute("src", OPAC_URL) 
}

/* shoves data into the OPAC's space */
function set_opac_vars() {
	var p = opac_page_thing;
	p.opac_iframe = p.w.document.getElementById('opac_opac_iframe');
	p.opac_iframe.contentWindow.IAMXUL = true;
	p.opac_iframe.contentWindow.xulG = mw.G;
	p.opac_iframe.contentWindow.attachEvt("rresult", "recordDrawn", opac_make_details_page);
}

function opac_make_details_page(id, node) {
	//dump("Node HREF attribute is: " + node.getAttribute("href") + "\n and doc id is " + id);
	//alert("Node HREF attribute is: " + node.getAttribute("href") + "\n and doc id is " + id);
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








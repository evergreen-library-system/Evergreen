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
	p.opac_iframe.contentWindow.makeXULLink = makeXULLink;
	p.opac_iframe.contentWindow.xulG = mw.G;
}

/* build a XUL specific link within the OPAC.
	@param type The type of link to build
	@param node The DOM node (<a>..</a>, most likely) whose onclick you wish to set
	@param thing The data need to set the action for the specific type.  For
		example, 'thing' is the record id for 'marc' and 'copy' types.
*/
function makeXULLink(type, node, thing) {

	var p = opac_page_thing;
	switch(type) {

		case "marc":
			node.onclick = function(thing) { 
				spawn_marc_editor( 
					p.w.app_shell, 'new_tab', 'main_tabbox', 
						{ 'find_this_id' : thing } ).find_this_id = thing;
			};
			break;

		case "copy":
			node.onclick = function(thing) { 
				spawn_copy_browser(
					p.w.app_shell, 'new_tab', 'main_tabbox', 
						{ 'find_this_id' : thing }).find_this_id = thing;
			};
			break;
	}
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






/* -------------------------------------------------------------------------- 
	XUL Callbacks
	-------------------------------------------------------------------------- */

/*
function opac_build_callbacks(p) {
	p.xulEvtRecordResultDisplayed = function(ui_obj, record) {
		ui_obj.addItem("Edit MARC", function() { 
				spawn_marc_editor( 
					p.w.app_shell, 'new_tab', 'main_tabbox', { 
						'find_this_id' : record.doc_id() 
					} 
				).find_this_id = record.doc_id();
			}
		);

		ui_obj.addItem("Open Copy Browser", function() { 
				spawn_copy_browser(
					p.w.app_shell, 'new_tab', 'main_tabbox', {
						'find_this_id' : record.doc_id()
					}
				).find_this_id = record.doc_id();
			}
		);

	}

	p.xulEvtMRResultDisplayed = function(ui_obj, record) {
		sdump('D_OPAC',"xulEvtMRRsultsDisplayed()\n");
	}


	p.xulEvtRecordDetailDisplayed = function(ui_obj, record) {
		ui_obj.addItem("Edit MARC", function() { 
				spawn_marc_editor( 
					p.w.app_shell, 'new_tab', 'main_tabbox', { 
						'find_this_id' : record.doc_id() 
					} 
				).find_this_id = record.doc_id();
			}
		);

		ui_obj.addItem("Open Copy Browser", function() { 
				spawn_copy_browser(
					p.w.app_shell, 'new_tab', 'main_tabbox', {
						'find_this_id' : record.doc_id()
					}
				).find_this_id = record.doc_id();
			}
		);
	}

	p.xulEvtViewMARC = function( node, record ) {
		node.onclick = p.buildViewMARCWindow(record);
	}



	p.buildViewMARCWindow = function(record) {
	
   	debug("Setting up view marc with record " + record.doc_id());
	
   	var func = function() { marc_view(p.w.app_shell,record.doc_id()); }
   	return func;
	}


}
*/

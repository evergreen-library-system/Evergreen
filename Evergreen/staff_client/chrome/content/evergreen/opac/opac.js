sdump('D_OPAC','Loading opac.js\n');

var OPAC_URL = "http://dev.gapines.org/"

/* listen for page changes */

function buildProgressListener(p) {
	sdump('D_OPAC',arg_dump(arguments));
	var progressListener = {
		onProgressChange	: function(){},
		onLocationChange	: function(){},
		onStatusChange		: function(){},
		onSecurityChange	: function(){},
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
	progressListener.QueryInterface = function(){return this;};
	return progressListener;
}

/* init the opac */
function opac_init(p) {
	sdump('D_OPAC',"Initing OPAC\n");

	p.opac_progressListener = buildProgressListener(p);

	p.opac_iframe = p.w.document.getElementById('opac_opac_iframe');
	p.opac_iframe.addProgressListener(p.opac_progressListener, 
		Components.interfaces.nsIWebProgress.NOTIFY_ALL );
	p.opac_iframe.setAttribute("src", OPAC_URL + '?l=' + mw.G.user.home_ou()) 
}

/* shoves data into the OPAC's space */
function set_opac_vars(p) {
	sdump('D_OPAC',arg_dump(arguments));
	p.opac_iframe.contentWindow.IAMXUL = true;
	p.opac_iframe.contentWindow.xulG = mw.G;
	p.opac_iframe.contentWindow.attachEvt("rdetail", "recordRetrieved", 
		function(id){opac_make_details_page(p,id)});
	p.opac_iframe.removeProgressListener(p.opac_progressListener);
	p.opac_iframe.addProgressListener(p.opac_progressListener, 
		Components.interfaces.nsIWebProgress.NOTIFY_STATE_DOCUMENT );

}

function opac_make_details_page(p, id) {
	sdump('D_OPAC',arg_dump(arguments));
	dump("OPAC doc id is " + id +'\n');
	spawn_record_details(
		p.w.app_shell, 'new_tab', 'main_tabbox', {
			'find_this_id' : id
		}
	).find_this_id = id;
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








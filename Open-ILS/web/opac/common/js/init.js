
/* these events should be used by all */

window.onunload = windowUnload;

attachEvt("common", "init", loadUIObjects);
//attachEvt("common", "init", initParams);
attachEvt("common", "init", initCookies);

attachEvt("common", "unload", _tree_killer);
try{ attachEvt("common", "unload", cleanRemoteRequests);} catch(e){}

function init() {

	initParams();

	if( getLocation() == null && getOrigLocation() != null )
		LOCATION = getOrigLocation();

	if( getLocation() == null && getOrigLocation() == null )
		LOCATION = globalOrgTree.id();

	/* if they click on the home page and the origlocation is set
		take the opac back to the origlocation */
	if( findCurrentPage() == HOME && getOrigLocation() != null )
		LOCATION = getOrigLocation();

	if(getDepth() == null) DEPTH = findOrgDepth(getLocation());


	runEvt('common','init');

	var cgi = new CGI();
	if( grabUser() ) {
		if( cgi.param(PARAM_LOCATION) == null ) {
			var org = G.user.prefs[PREF_DEF_LOCATION];
			var depth = G.user.prefs[PREF_DEF_DEPTH];

			if(org == null) org = G.user.ws_ou();
			if(depth == null) depth = findOrgDepth(org);

			LOCATION = org;
			DEPTH = depth;
		}
	}

	// show_login trumps normal page running
	if(location.href.match(/&show_login=1/)) {
		function reload() {
			var src = location.href.replace(/&show_login=1/, '');
			// forceLoginSSL setting (indicated by show_login)
			// assumes we are not SSL on normal pages
			src = src.replace(/https:/, 'http:');
			goTo(src);
		}
		attachEvt("common", "loginCanceled", reload);
		initLogin();
	} else {
		runEvt("common", "run");
	}
	//checkUserSkin();

	var loc = findOrgLasso(getLasso());
	if (!loc) loc = findOrgUnit(getLocation());

	if (getLasso()) G.ui.common.now_searching.appendChild(text('Search group: '));
	G.ui.common.now_searching.appendChild(text(loc.name()));
}

function windowUnload() { runEvt("common", "unload"); }

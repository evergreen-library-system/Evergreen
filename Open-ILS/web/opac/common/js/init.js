
/* these events should be used by all */

window.onunload = windowUnload;

attachEvt("common", "init", loadUIObjects);
attachEvt("common", "init", initParams);
attachEvt("common", "init", initCookies);

attachEvt("common", "unload", _tree_killer);
try{ attachEvt("common", "unload", cleanRemoteRequests);} catch(e){}

function init() {

	runEvt('common','init');
	if( getOrigLocation() == 0 ) ORIGLOC = LOCATION;

	var cgi = new CGI();
	if( grabUser() ) {
		if( cgi.param(PARAM_LOCATION) == null ) {
			var org = G.user.prefs[PREF_DEF_LOCATION];
			var depth = G.user.prefs[PREF_DEF_DEPTH];

			if(!org) org = G.use.ws_ou();
			if(!depth) depth = findOrgDepth(org);

			LOCATION = org;
			DEPTH = DEPTH;
		}
	}

	runEvt("common", "run");
	//checkUserSkin();
	G.ui.common.now_searching.appendChild(text(findOrgUnit(getLocation()).name()));
}

function windowUnload() { runEvt("common", "unload"); }

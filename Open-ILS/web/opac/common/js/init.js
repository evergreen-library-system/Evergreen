
/* these events should be used by all */

window.onunload = windowUnload;

attachEvt("common", "init", loadUIObjects);
attachEvt("common", "init", initParams);
attachEvt("common", "init", initCookies);
//attachEvt("common", "init", drawOrgTree); 

attachEvt("common", "unload", _tree_killer);
try{ attachEvt("common", "unload", cleanRemoteRequests);} catch(e){}

function init() {
	runEvt('common','init');
	if( getOrigLocation() == 0 ) ORIGLOC = LOCATION;
	runEvt("common", "run");
	//checkUserSkin();
	G.ui.common.now_searching.appendChild(text(findOrgUnit(getLocation()).name()));
}

function windowUnload() { runEvt("common", "unload"); }

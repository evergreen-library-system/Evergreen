
/* these events should be used by all */

window.onunload = windowUnload;

attachEvt("common", "init", loadUIObjects);
attachEvt("common", "init", initParams);
attachEvt("common", "init", initCookies);
attachEvt("common", "init", drawOrgTree); 

//attachEvt("common", "unload", _tree_killer);
//attachEvt("common", "unload", clearUIObjects);
//attachEvt("common", "unload", cleanRemoteRequests);

function init() {
	runEvt('common','init');
	setFontSize(getFontSize());
	runEvt("common", "run");
	checkUserSkin();
}

function windowUnload() { runEvt("common", "unload"); }

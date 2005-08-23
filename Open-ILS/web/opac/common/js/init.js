
/* these events should be used by all */

window.onunload = windowUnload;

attachEvt("common", "init", loadUIObjects);
attachEvt("common", "init", initParams);
attachEvt("common", "init", drawOrgTree); 
attachEvt("common", "unload", _tree_killer);
attachEvt("common", "unload", clearUIObjects);
attachEvt("common", "unload", cleanRemoteRequests);

function init() {
	runEvt('common','init');
	scaleFont("medium");
	switch(findCurrentPage()) {
		case MRESULT: runEvt('mresult', 'run'); break;
		case RRESULT: runEvt('rresult', 'run'); break;
	}
}

function windowUnload() { runEvt("common", "unload"); }

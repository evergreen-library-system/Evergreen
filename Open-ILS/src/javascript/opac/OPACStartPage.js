OPACStartPage.prototype					= new Page();
OPACStartPage.prototype.constructor	= OPACStartPage;
OPACStartPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// opac_start
// ---------------------------------------------------------------------------------

var globalOPACStartPage = null;

function OPACStartPage() {

	debug("In OPACStartPage()");
	//this.searchBar			= new SearchBarChunk();
	this.searchBrFormChunk = new SearchBarFormChunk();

	if( globalOPACStartPage ) {
		return globalOPACStartPage; 
	}

	globalOPACStartPage = this;
}

OPACStartPage.prototype.instance = function() {
	if( globalOPACStartPage ) 
		return globalOPACStartPage; 

	return new OPACStartPage();
}

OPACStartPage.prototype.init = function() {
	//this.searchBar.reset();
	globalSearchBarFormChunk.resetPage();
	/*
	var menu = globalMenuManager.buildMenu("record_result_row","record_result_row_1");
	globalAppFrame.document.body.appendChild(menu.getNode());
	getById('help').setAttribute("oncontextmenu",  
		"logicNode.globalMenuManager.getMenu('record_result_row_1').toggle(); return false;");
		*/
}


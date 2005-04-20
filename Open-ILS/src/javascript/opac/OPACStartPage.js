OPACStartPage.prototype					= new Page();
OPACStartPage.prototype.constructor	= OPACStartPage;
OPACStartPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// opac_start
// ---------------------------------------------------------------------------------

var globalOPACStartPage = null;

function OPACStartPage() {

	debug("In OPACStartPage()");
	this.searchBar			= new SearchBarChunk();

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
	this.searchBar.reset();
	globalSearchBarFormChunk.resetPage();
}


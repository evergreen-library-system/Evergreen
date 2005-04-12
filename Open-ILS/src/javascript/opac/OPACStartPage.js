OPACStartPage.prototype					= new Page();
OPACStartPage.prototype.constructor	= OPACStartPage;
OPACStartPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// opac_start
// ---------------------------------------------------------------------------------

var globalOPACStartPage = null;

function OPACStartPage() {

	if( globalOPACStartPage ) 
		return globalOPACStartPage; 

	this.searchBarForm	= new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();
	globalOPACStartPage = this;
}

OPACStartPage.prototype.instance = function() {
	if( globalOPACStartPage ) 
		return globalOPACStartPage; 

	return new OPACStartPage();
}


MyOPACPage.prototype					= new Page();
MyOPACPage.prototype.constructor	= MyOPACPage;
MyOPACPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// my_opac
// ---------------------------------------------------------------------------------
function MyOPACPage() {
	this.searhBarForm = new SearchBarFormChunk();
	this.searchBar = new SearchBarChunk();
}



AboutPage.prototype					= new Page();
AboutPage.prototype.constructor	= AboutPage;
AboutPage.baseClass					= Page.constructor;

function AboutPage() {
	this.searchBarForm	= new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();
}

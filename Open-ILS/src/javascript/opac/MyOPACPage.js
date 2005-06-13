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

MyOPACPage.prototype.redirect = function() {
	var frame = getById("my_opac_iframe");
	var source = "https://gapines.org/opac/?target=my_opac_secure";
	source += "&session=" + UserSession.instance().getSessionId();
	frame.setAttribute("src",source);
	return true;
}



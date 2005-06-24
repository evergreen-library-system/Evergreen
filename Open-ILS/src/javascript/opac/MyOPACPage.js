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

	var org = globalSelectedLocation;
	if(org == null)
		org = globalLocation;
	org = org.id();
	var depth = globalSearchDepth;

	var source = "https://" + globalRootURL + globalRootPath 
		+ "?target=my_opac_secure" + "&location=" + org + "&depth=" + depth;

	source += "&session=" + UserSession.instance().getSessionId();
	frame.setAttribute("src",source);
	return true;
}



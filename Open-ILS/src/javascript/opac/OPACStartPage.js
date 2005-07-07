OPACStartPage.prototype					= new Page();
OPACStartPage.prototype.constructor	= OPACStartPage;
OPACStartPage.baseClass					= Page.constructor;

try {
	if(parent) 
		parent.OPACStartPage = OPACStartPage;
} catch(E){}

try {
	if(child)
		child.OPACStartPage = OPACStartPage;
} catch(E){}


// ---------------------------------------------------------------------------------
// opac_start
// ---------------------------------------------------------------------------------

var globalOPACStartPage = null;

		
function OPACStartPage() {

	debug("In OPACStartPage()");
	this.searchBrFormChunk = new SearchBarFormChunk();

	if( globalOPACStartPage ) {
		return globalOPACStartPage; 
	}

	this.init();
	globalOPACStartPage = this;
}

OPACStartPage.prototype.instance = function() {
	if( globalOPACStartPage ) 
		return globalOPACStartPage; 

	return new OPACStartPage();
}

OPACStartPage.prototype.init = function() {

	globalSearchBarFormChunk.resetPage();
	var login = getById("login_link");

	if(!UserSession.instance().verifySession()) {
		login.setAttribute("href","javascript:void(0);");
		var func = function(){url_redirect(["target","my_opac"])};
		var diag = new LoginDialog(func);
		login.onclick = function(){diag.display(login);}
	}
}


OPACStartPage.prototype.doSearch = function() {
}

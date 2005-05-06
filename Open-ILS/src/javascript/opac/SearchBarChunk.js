var globalSearchBarChunk = null;

function SearchBarChunk() {

	debug("In SearchBarChunk()");

	this.searchBarForm = new SearchBarFormChunk();

	/* this links */
	this.search_link		= getById("adv_search_link");
	this.login_link		= getById("login_link");
	this.my_opac_link		= getById("my_opac_link");
	this.about_link		= getById("about_link");
	this.logout_link		= getById("logout_link");

	/* divs for the links */
	this.adv_search_link_div	= getById("adv_search_link_div");
	this.my_opac_link_div		= getById("my_opac_link_div");
	this.about_link_div			= getById("about_link_div");
	this.login_div					= getById("login_div");
	this.logout_div				= getById("logout_div");

	if(globalSearchBarChunk == null)
		try { this.session = UserSession.instance(); } catch(E) {}
	else
		this.session = globalSearchBarChunk.session;

	globalSearchBarChunk = this;
}

SearchBarChunk.prototype.reset = function() {
	
	if( this.session.connected ) {
		debug(" ****** session is connected");
		hideMe(this.login_div);
		showMe(this.logout_div);

	} else { 
		debug(" ****** session is not connected");
		showMe(this.login_div);
		hideMe(this.logout_div);

	}
}

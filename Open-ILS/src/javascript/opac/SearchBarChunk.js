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

	debug("^^^^^^^^^^^^");
	this.reset();

	globalSearchBarChunk = this;
}


SearchBarChunk.prototype.reset = function() {
	
	debug("  -- reset on SearchBarChunk");

	if( this.session.connected ) {
		debug(" ****** session is connected");
		hideMe(this.login_div);
		showMe(this.logout_div);

	} else { 
		debug(" ****** session is not connected");
		showMe(this.login_div);
		hideMe(this.logout_div);
	}

	if(isXUL()) {
		debug("Hiding search bar links since we're XUL");
		hideMe(this.login_div);
		hideMe(this.logout_div);
		hideMe(this.my_opac_link_div);
		hideMe(this.about_link_div);
	}
}

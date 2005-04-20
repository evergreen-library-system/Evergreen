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
		this.session = UserSession.instance();
	else
		this.session = globalSearchBarChunk.session;

	//this.reset();
	globalSearchBarChunk = this;
}

SearchBarChunk.prototype.reset = function() {

	
	var red_func = function() {this.className = "color_red";};
	var blue_func = function() {this.className = "color_blue";};

	var activeclass = "choice_activated";
	remove_css_class(this.adv_search_link_div, activeclass);
	remove_css_class(this.login_div,				 activeclass);
	remove_css_class(this.logout_div, 			 activeclass);
	remove_css_class(this.about_link_div, 		 activeclass);
	remove_css_class(this.my_opac_link_div, 	 activeclass);

	switch(globalPageTarget) {

		case "advanced_search":
			add_css_class(this.adv_search_link_div, activeclass);
			break;

		case "login":
			add_css_class(this.login_div,	activeclass);
			break;

		case "logout":
			add_css_class(this.logout_div, activeclass);
			break;

		case "about":
			add_css_class(this.about_link_div, activeclass);
			break;

		case "my_opac":
			add_css_class(this.my_opac_link_div, activeclass);
			break;
	}


	this.search_link.className		= "color_red";
	this.search_link.onmouseout	= red_func;
	this.search_link.onmouseover	= blue_func; 

	this.login_link.className		= "color_red";
	this.login_link.onmouseout		= red_func;
	this.login_link.onmouseover	= blue_func;

	this.logout_link.className		= "color_red";
	this.logout_link.onmouseout	= red_func;
	this.logout_link.onmouseover	= blue_func;

	this.my_opac_link.className	= "color_red";
	this.my_opac_link.onmouseout	= red_func;
	this.my_opac_link.onmouseover	= blue_func;

	this.about_link.className		= "color_red";
	this.about_link.onmouseout		= red_func;
	this.about_link.onmouseover	= blue_func;

	if( this.session.connected ) {

		debug(" ****** session is connected");
		this.login_div.style.visibility		= "hidden";
		this.login_div.style.display			= "none";
		this.logout_div.style.visibility		= "visible";
		this.logout_div.style.display			= "block";

	} else { 
		debug(" ****** session is not connected");

		this.login_div.style.visibility		= "visible";
		this.login_div.style.display			= "block";
		this.logout_div.style.visibility		= "hidden";
		this.logout_div.style.display			= "none";

	}
}

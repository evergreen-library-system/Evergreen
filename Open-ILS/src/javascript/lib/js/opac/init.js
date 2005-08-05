
function init() {

	document.body.onunload = unload;

	loadUIObjects();
	initParams();
	initSideBar();
	searchBarInit();

	var page = findCurrentPage();
	switch(findCurrentPage()) {
		case MRESULT: mresultDoSearch(); break;
		case RRESULT: rresultDoSearch(); break;
	}

}

function unload() {

	_tree_killer();

	if(G.ui.sidebar.login)
		G.ui.sidebar.login.onclick		= null;
	if(G.ui.sidebar.logout)
		G.ui.sidebar.logout.onclick	= null;
	if(G.ui.login.button)
		G.ui.login.button.onclick		= null;
	if(G.ui.login.cancel)
		G.ui.login.cancel.onclick		= null;
	if(G.ui.searchbar.submit)
		G.ui.searchbar.submit.onclick = null;
	if(G.ui.searchbar.tag)
		G.ui.searchbar.tag.onclick		= null;

	clearUIObjects();

	if(IE) {
		window.CollectGarbage();
	}
}


/* set up the colors in the sidebar 
	Disables/Enables certain components based on various state data 
 */
function initSideBar() {

	for( var p in G.ui.sidebar ) 
		removeCSSClass(p, config.css.sidebar.item.active);

	var page = findCurrentPage();
	unHideMe(G.ui.sidebar[page]);
	addCSSClass(G.ui.sidebar[page], config.css.sidebar.item.active);

	/* if we're logged in, show it and replace the Login link with the Logout link */
	if(grabUser()) {
		G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
		unHideMe(G.ui.sidebar.logoutbox);
		unHideMe(G.ui.sidebar.logged_in_as);
		hideMe(G.ui.sidebar.loginbox);
	}

	if(G.ui.sidebar.login) G.ui.sidebar.login.onclick = initLogin;
	if(G.ui.sidebar.logout) G.ui.sidebar.logout.onclick = doLogout; 

}

/* sets up the login ui components */
function initLogin() {

	G.ui.login.button.onclick = function(){
		if(doLogin()) {
			unHideMe(G.ui.all.canvas_main);
			hideMe(G.ui.login.box);
			hideMe(G.ui.all.loading);

			G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
			unHideMe(G.ui.sidebar.logoutbox);
			unHideMe(G.ui.sidebar.logged_in_as);
			hideMe(G.ui.sidebar.loginbox);
		}
	}

	hideMe(G.ui.all.canvas_main);
	unHideMe(G.ui.login.box);

	G.ui.login.cancel.onclick = function(){
		unHideMe(G.ui.all.canvas_main);
		hideMe(G.ui.login.box);
		hideMe(G.ui.all.loading);
	}
}



/* sets all of the params values */
var TERM,  STYPE,  LOCATION,  DEPTH,  FORM, OFFSET,  COUNT,  
	 HITCOUNT,  RANKS, SEARCHBAR_EXTRAS;

function initParams() {
	var cgi	= new CGI();	

	TERM	= cgi.param(PARAM_TERM);
	STYPE	= cgi.param(PARAM_STYPE);
	FORM	= cgi.param(PARAM_FORM);

	LOCATION	= parseInt(cgi.param(PARAM_LOCATION));
	DEPTH		= parseInt(cgi.param(PARAM_DEPTH));
	OFFSET	= parseInt(cgi.param(PARAM_OFFSET));
	COUNT		= parseInt(cgi.param(PARAM_COUNT));
	HITCOUNT	= parseInt(cgi.param(PARAM_HITCOUNT));
	MRID		= parseInt(cgi.param(PARAM_MRID));
	RID		= parseInt(cgi.param(PARAM_RID));

	/* set up some sane defaults */
	if(isNaN(LOCATION))	LOCATION	= 1;
	if(isNaN(DEPTH))		DEPTH		= 0;
	if(isNaN(OFFSET))		OFFSET	= 0;
	if(isNaN(COUNT))		COUNT		= 10;
	if(isNaN(HITCOUNT))	HITCOUNT	= 0;
	if(isNaN(SEARCHBAR_EXTRAS))	SEARCHBAR_EXTRAS	= 0;
	if(isNaN(MRID))		MRID		= 0;
	if(isNaN(RID))			RID		= 0;
}

/* URL param accessors */
function getTerm(){return TERM;}
function getStype(){return STYPE;}
function getLocation(){return LOCATION;}
function getDepth(){return DEPTH;}
function getForm(){return FORM;}
function getOffset(){return OFFSET;}
function getDisplayCount(){return COUNT;}
function getHitCount(){return HITCOUNT;}
function getSearchBarExtras(){return SEARCHBAR_EXTRAS;}
function getMrid(){return MRID;};
function getRid(){return RID;};





function init() {

	loadUIObjects();
	initParams();
	initSideBar();
	searchBarInit();

	var login = G.ui.sidebar.login
	if(login) login.onclick = initLogin;

	if(grabUser()) {
		unHideMe(G.ui.sidebar.logged_in_as);
		G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
	}

	var page = findCurrentPage();
	switch(findCurrentPage()) {
		case MRESULT: mresultDoSearch(); break;
		case RRESULT: rresultDoSearch(); break;
	}

}

/* sets up the login ui components */
function initLogin() {


	G.ui.login.button.onclick = function(){
		if(doLogin()) {
			unHideMe(G.ui.all.canvas_main);
			hideMe(G.ui.login.box);
			hideMe(G.ui.all.loading);

			unHideMe(G.ui.sidebar.logged_in_as);
			G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
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


/* set up the colors in the sidebar */
function initSideBar() {
	for( var p in G.ui.sidebar ) 
		removeCSSClass(p, config.css.sidebar.item.active);

	var page = findCurrentPage();
	addCSSClass(G.ui.sidebar[page], config.css.sidebar.item.active);
	removeCSSClass(G.ui.sidebar[page], config.css.hide_me);
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




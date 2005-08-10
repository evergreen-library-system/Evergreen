
function init() {

	document.body.onunload = unload;
	window.onunload = unload;

	loadUIObjects();
	initParams();
	initSideBar();
	searchBarInit();
	G.ui.common.org_tree.innerHTML = buildOrgSelector().toString();

	switch(findCurrentPage()) {
		case MRESULT: mresultDoSearch(); break;
		case RRESULT: rresultDoSearch(); break;
	}

}

/* free whatever memory we can */
function unload() {
	_tree_killer();
	clearUIObjects();
	cleanRemoteRequests();
	try{mresultUnload();} catch(E){}
}


/* set up the colors in the sidebar 
	Disables/Enables certain components based on various state data 
 */
function initSideBar() {

	for( var p in G.ui.sidebar ) 
		removeCSSClass(p, config.css.color_2);

	var page = findCurrentPage();
	unHideMe(G.ui.sidebar[page]);
	addCSSClass(G.ui.sidebar[page], config.css.color_2);

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
var loginBoxVisible = false;
function initLogin() {

	var loginDance = function() {
		if(doLogin()) {
			showCanvas();
			G.ui.sidebar.username_dest.appendChild(text(G.user.usrname()));
			unHideMe(G.ui.sidebar.logoutbox);
			unHideMe(G.ui.sidebar.logged_in_as);
			hideMe(G.ui.sidebar.loginbox);
		}
	}

	G.ui.login.button.onclick = loginDance;
	G.ui.login.username.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};
	G.ui.login.password.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) loginDance();};

	if(loginBoxVisible) {
		showCanvas();
	} else {
		swapCanvas(G.ui.login.box);
		G.ui.login.username.focus();
	}
	loginBoxVisible = !loginBoxVisible;
	G.ui.login.cancel.onclick = showCanvas;
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




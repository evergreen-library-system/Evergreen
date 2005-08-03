
function init() {
	initParams();
	var page = findCurrentPage();
	initSideBar(config.ids.sidebar[page]);
	searchBarInit();

	var login_div = getId(config.ids.sidebar.login);
	if(login_div) login_div.onclick = initLogin;

	switch(page) {
		case MRESULT: mresultDoSearch(); break;
		case RRESULT: rresultDoSearch(); break;
	}

}

function initLogin() {
	config.ids.login.button.onclick = function(){doLogin();}
	addCSSClass(getId(config.ids.canvas_main), config.css.hide_me);
	removeCSSClass(getId(config.ids.login.box), config.css.hide_me);
}


/* set up the colors in the sidebar */
function initSideBar() {
	for( var p in config.ids.sidebar ) {
		var page = config.ids.sidebar[p];
		removeCSSClass(getId(page), config.css.sidebar.item.active);
	}
	var page = findCurrentPage();
	addCSSClass(getId(config.ids.sidebar[page]), config.css.sidebar.item.active);
	removeCSSClass(getId(config.ids.sidebar[page]), config.css.hide_me);
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




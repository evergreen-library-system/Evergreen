var IAMXUL = false;
function isXUL() { return IAMXUL; }


/* - Request ------------------------------------------------------------- */
function Request(type) {
	var s = type.split(":");
	if(s[2] == "1" && isXUL()) s[1] += ".staff";
	this.request = new RemoteRequest(s[0], s[1]);
	for( var x = 1; x!= arguments.length; x++ ) 
		this.request.addParam(arguments[x]);
}

Request.prototype.callback = function(cal) { this.request.setCompleteCallback(cal); }
Request.prototype.send		= function(block){this.request.send(block);}
Request.prototype.result	= function(){return this.request.getResultObject();}
/* ----------------------------------------------------------------------- */

function showCanvas() { setTimeout(_showCanvas, 200); }
function _showCanvas() {
	for( var x in G.ui.altcanvas ) {
		hideMe(G.ui.altcanvas[x]);
	}
	hideMe(G.ui.common.loading);
	unHideMe(G.ui.common.canvas_main);
	G.ui.searchbar.text.focus(); 
}

var newCanvasNode;
function swapCanvas(newNode) { newCanvasNode = newNode; setTimeout(_swapCanvas, 200); }
function _swapCanvas() {
	for( var x in G.ui.altcanvas ) 
		hideMe(G.ui.altcanvas[x]);

	hideMe(G.ui.common.loading);
	hideMe(G.ui.common.canvas_main);
	unHideMe(newCanvasNode);
}

/* finds the name of the current page */
var currentPage = null;
function findCurrentPage() {
	if(currentPage) return currentPage;

	var pages = [];
	for( var p in config.page ) pages.push(config.page[p]);
	pages = pages.sort( function(a,b){ return - (a.length - b.length); } );

	var path = location.pathname;
	if(!path.match(/.*\.xml$/))
		path += "index.xml"; /* in case they go to  / */

	var page = null;
	for( var p in pages ) {
		if( path.indexOf(pages[p]) != -1)
			page = pages[p];
	}

	for( var p in config.page ) {
		if(config.page[p] == page) {
			currentPage = p;
			return p;
		}
	}

	return null;
}


/* sets all of the params values  ----------------------------- */
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



/* builds an opac URL.  If no page is defined, the current page is used
	if slim, then only everything after the ? is returned (no host portion) */
function findBasePath() {
	var path = location.pathname;
	if(!path.match(/.*\.xml$/)) path += "index.xml"; 
	var idx = path.indexOf(config.page[findCurrentPage()]);
	return path.substring(0, idx);
}

function findBaseURL(ssl) {
	var path = findBasePath();
	var proto = location.protocol;
	if(ssl) proto = "https";
	return location.protocol + "//" + location.host + path;
}

function buildImageLink(name, ssl) {
	return findBaseURL(ssl) + "../../../images/" + name;
}

function  buildOPACLink(args, slim, ssl) {

	if(!args) args = {};
	var string = "";

	if(!slim) {
		string = findBaseURL(ssl);
		if(args.page) string += config.page[args.page];
		else string += config.page[findCurrentPage()];
	}

	string += "?";

	for( var x in args ) {
		if(x == "page" || args[x] == null) continue;
		string += "&" + x + "=" + encodeURIComponent(args[x]);
	}

	string += _appendParam(TERM,		PARAM_TERM, args, getTerm, string);
	string += _appendParam(STYPE,		PARAM_STYPE, args, getStype, string);
	string += _appendParam(LOCATION, PARAM_LOCATION, args, getLocation, string);
	string += _appendParam(DEPTH,		PARAM_DEPTH, args, getDepth, string);
	string += _appendParam(FORM,		PARAM_FORM, args, getForm, string);
	string += _appendParam(OFFSET,	PARAM_OFFSET, args, getOffset, string);
	string += _appendParam(COUNT,		PARAM_COUNT, args, getDisplayCount, string);
	string += _appendParam(HITCOUNT, PARAM_HITCOUNT, args, getHitCount, string);
	string += _appendParam(MRID,		PARAM_MRID, args, getMrid, string);
	string += _appendParam(RID,		PARAM_RID, args, getRid, string);
	return string.replace(/\&$/,'').replace(/\?\&/,"?");	
}

function _appendParam( fieldVar, fieldName, overrideArgs, getFunc, string ) {
	var ret = "";
	if( fieldVar != null && overrideArgs[fieldName] == null ) 
		ret = "&" + fieldName + "=" + encodeURIComponent(getFunc());
	return ret;
}


function EX(message) { this.init(message); }
EX.prototype.init = function(message) { this.message = message; }
EX.prototype.toString = function() { return "\n *** Exception Occured \n" + this.message; }  
EXCommunication.prototype              = new EX();
EXCommunication.prototype.constructor  = EXCommunication;
EXCommunication.baseClass              = EX.prototype.constructor;
function EXCommunication(message) { this.init("EXCommunication: " + message); }                          

/* ----------------------------------------------------------------------- */
function cleanISBN(isbn) {
   if(isbn) {
      isbn = isbn.toString().replace(/^\s+/,"");
      var idx = isbn.indexOf(" ");
      if(idx > -1) { isbn = isbn.substring(0, idx); }
   } else isbn = "";
   return isbn;
}       




/* builds a link that goes to the title listings for a metarecord */
function buildTitleLink(rec, link) {
	if(!rec) return;
	link.appendChild(text(normalize(truncate(rec.title(), 65))));
	var args = {};
	args.page = RRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_MRID] = rec.doc_id();
	link.setAttribute("href", buildOPACLink(args));
}

function buildTitleDetailLink(rec, link) {
	if(!rec) return;
	link.appendChild(text(normalize(truncate(rec.title(), 65))));
	var args = {};
	args.page = RDETAIL;
	args[PARAM_OFFSET] = 0;
	args[PARAM_RID] = rec.doc_id();
	link.setAttribute("href", buildOPACLink(args));
}

/* 'type' is one of STYPE_AUTHOR, STYPE_SUBJECT, ... found in config.js 
	'trunc' is the number of characters to show in the string, defaults to 65 */
function buildSearchLink(type, string, linknode, trunc) {
	if(!trunc) trunc = 65;
	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = string;
	args[PARAM_STYPE] = type;
	linknode.appendChild(text(normalize(truncate(string, trunc))));
	linknode.setAttribute("href", buildOPACLink(args));
}


/* ----------------------------------------------------------------------- */
/* user session handling */
/* ----------------------------------------------------------------------- */

/* session is the login session.  If no session is provided, we attempt
	to find one in the cookies.  If 'force' is true we retrieve the 
	user from the server even if there is already a global user present.
	if ses != G.user.session, we also force a grab */
var cookie = new cookieObject("ses", 1, "/", COOKIE_SES);
function grabUser(ses, force) {

	if(!ses) ses = cookie.get(COOKIE_SES);
	if(!ses) return false;

	if(!force) 
		if(G.user && G.user.session == ses)
			return G.user;

	/* first make sure the session is valid */
	var request = new Request(FETCH_SESSION, ses );
	request.send(true);
	var user = request.result();
	if( !(typeof user == 'object' && user._isfieldmapper) ) {
		return false;
	}

	G.user = user;
	G.user.fleshed = false;
	G.user.session = ses;
	cookie.put(COOKIE_SES, ses);
	cookie.write();

	return G.user;

}

function grabFleshedUser() {

	if(!G.user || !G.user.session) {
		grabUser();	
		if(!G.user || !G.user.session) return null;
	}

	if(G.user.fleshed) return G.user;

   var req = new Request(FETCH_FLESHED_USER, G.user.session);
  	req.send(true);

  	G.user = req.result();

	if(!G.user || G.user.length == 0) { 
		G.user = null; return false; 
		cookie.remove(COOKIE_SES);
	}

	G.user.session = ses;
	G.user.fleshed = true;

	cookie.put(COOKIE_SES, ses); /*  update the cookie */
	cookie.write();

	return G.user;
}


/* returns a fleshed G.user on success, false on failure */
function doLogin() {

	var uname = G.ui.login.username.value;
	var passwd = G.ui.login.password.value;	

	var init_request = new Request( LOGIN_INIT, uname );
   init_request.send(true);
   var seed = init_request.result();

   if( ! seed || seed == '0') {
      alert( "Error Communicating with Authentication Server" );
      return null;
   }

   var auth_request = new Request( LOGIN_COMPLETE, 
		uname, hex_md5(seed + hex_md5(passwd)), "opac");

   auth_request.send(true);
   var auth_result = auth_request.result();

   if(auth_result == '0' || auth_result == null || auth_result.length == 0) { return false; }

	var u = grabUser(auth_result, true);
	if(u) updateLoc(u.home_ou(), findOrgDepth(u.home_ou()));

	return u;
}

function doLogout() {

	/* be nice and delete the session from the server */
	if(G.user && G.user.session) { 
		var req = new Request(LOGIN_DELETE, G.user.session);
      req.send(true);
		try { req.result(); } catch(E){}
    }

	G.user = null;
	cookie.remove(COOKIE_SES);

	hideMe(G.ui.sidebar.logoutbox);
	unHideMe(G.ui.sidebar.loginbox);
	hideMe(G.ui.sidebar.logged_in_as);

}


function hideMe(obj) { addCSSClass(obj, config.css.hide_me); } 
function unHideMe(obj) { removeCSSClass(obj, config.css.hide_me); }


/* ----------------------------------------------------------------------- */
/* build the org tree */
/* ----------------------------------------------------------------------- */


function drawOrgTree() {
	G.ui.common.org_tree.innerHTML = buildOrgSelector().toString();
}
	
var orgTreeSelector;
function buildOrgSelector() {
	var tree = new dTree("orgTreeSelector"); 
	for( var i in orgArraySearcher ) { 
		var node = orgArraySearcher[i];
		if( node == null ) continue;
		if(node.parent_ou() == null)
			tree.add(node.id(), -1, node.name(), 
				"javascript:orgSelect(" + node.id() + ");", node.name());
		else {
			tree.add(node.id(), node.parent_ou().id(), node.name(), 
				"javascript:orgSelect(" + node.id() + ");", node.name());
		}
	}
	orgTreeSelector = tree;
	return tree;
}

function orgSelect(id) {
	showCanvas();
	updateLoc(id, findOrgDepth(id));
}


/* ------------------------------------------------------------------------------------------------------ */
/* org tree utilities */
/* ------------------------------------------------------------------------------------------------------ */

/* takes an org unit or id and return the numeric depth */
function findOrgDepth(org_id_or_node) {
	return findOrgType(findOrgUnit(org_id_or_node).ou_type()).depth();
}

/* takes the org type id from orgunit.ou_type() field and returns
	the org type object */
function findOrgType(type_id) {
	if(typeof type_id == 'object') return type_id;
	for(var type in globalOrgTypes) {
		var t =globalOrgTypes[type]; 
		if( t.id() == type_id || t.id() == parseInt(type_id) ) 
			return t;
	}
	return null;
}


/* returns an org unit by id.  if an object is passed in as the id,
	then the object is assumed to be an org unit and is returned */
function findOrgUnit(org_id) {
	return (typeof org_id == 'object') ? org_id : orgArraySearcher[org_id];
}


/* builds a trail from the top of the org tree to the node provide.
	basically fleshes out 'my orgs' 
	Returns an array of [org0, org1, ..., myorg] */
function orgNodeTrail(node) {
	var na = new Array();
	while( node ) {
		na.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	return na.reverse();
}


/* returns an array of sibling org units */
function findSiblingOrgs(node) { return findOrgUnit(node.parent_ou()).children(); }
/* ------------------------------------------------------------------------------------------------------ */








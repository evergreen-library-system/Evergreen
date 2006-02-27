/* - Request ------------------------------------------------------------- */

/* define it again here for pages that don't load RemoteRequest */
function isXUL() { try { if(IAMXUL) return true;}catch(e){return false;}; }

var cookieManager = new HTTP.Cookies();

var __ilsEvent; /* the last event the occurred */

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

function showCanvas() {
	for( var x in G.ui.altcanvas ) {
		hideMe(G.ui.altcanvas[x]);
	}
	hideMe(G.ui.common.loading);
	unHideMe(G.ui.common.canvas_main);
	try{G.ui.searchbar.text.focus();}catch(e){}
}

function swapCanvas(newNode) {
	for( var x in G.ui.altcanvas ) 
		hideMe(G.ui.altcanvas[x]);

	hideMe(G.ui.common.loading);
	hideMe(G.ui.common.canvas_main);
	unHideMe(newNode);
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
function initParams() {
	var cgi	= new CGI();	

	TERM	= cgi.param(PARAM_TERM);
	STYPE	= cgi.param(PARAM_STYPE);
	FORM	= cgi.param(PARAM_FORM);

	LOCATION	= parseInt(cgi.param(PARAM_LOCATION));
	ORIGLOC	= parseInt(cgi.param(PARAM_ORIGLOC));
	DEPTH		= parseInt(cgi.param(PARAM_DEPTH));
	OFFSET	= parseInt(cgi.param(PARAM_OFFSET));
	COUNT		= parseInt(cgi.param(PARAM_COUNT));
	HITCOUNT	= parseInt(cgi.param(PARAM_HITCOUNT));
	MRID		= parseInt(cgi.param(PARAM_MRID));
	RID		= parseInt(cgi.param(PARAM_RID));
	TOPRANK  = parseFloat(cgi.param(PARAM_TOPRANK));
	AUTHTIME	= parseInt(cgi.param(PARAM_AUTHTIME));
	ADVTERM	= cgi.param(PARAM_ADVTERM);
	ADVTYPE	= cgi.param(PARAM_ADVTYPE);

	/* set up some sane defaults */
	if(isNaN(LOCATION))	LOCATION	= 1;
	if(isNaN(DEPTH))		DEPTH		= 0;
	if(isNaN(OFFSET))		OFFSET	= 0;
	if(isNaN(COUNT))		COUNT		= 10;
	if(isNaN(HITCOUNT))	HITCOUNT	= 0;
	if(isNaN(MRID))		MRID		= 0;
	if(isNaN(RID))			RID		= 0;
	if(isNaN(ORIGLOC))	ORIGLOC	= 0;
	if(isNaN(TOPRANK))	TOPRANK	= 1;
	if(isNaN(AUTHTIME))	AUTHTIME	= 1;
	if(ADVTERM==null)		ADVTERM	= "";
}

function initCookies() {
	FONTSIZE = "medium";
	var font = cookieManager.read(COOKIE_FONT);
	if(font) FONTSIZE = font;
	SKIN = cookieManager.read(COOKIE_SKIN);
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
function getMrid(){return MRID;};
function getRid(){return RID;};
function getOrigLocation(){return ORIGLOC;}
function getTopRank(){return TOPRANK;}
function getAuthtime() { return AUTHTIME; }
function getSearchBarExtras(){return SBEXTRAS;}
function getFontSize(){return FONTSIZE;};
function getSkin(){return SKIN;};
function getAdvTerm(){return ADVTERM;}
function getAdvType(){return ADVTYPE;}


function findBasePath() {
	var path = location.pathname;
	if(!path.match(/.*\.xml$/)) path += "index.xml"; 
	var idx = path.indexOf(config.page[findCurrentPage()]);
	return path.substring(0, idx);
}

function findBaseURL(ssl) {
	var path = findBasePath();
	var proto = (ssl) ? "https:" : "http:";
	return proto + "//" + location.host + path;
	dump( 'ssl: ' + ssl + 'proto ' + proto );
}

/*
function buildISBNSrc(isbn) {
	return "http://" + location.host + "/jackets/" + isbn;
}
*/

function buildImageLink(name, ssl) {
	return findBaseURL(ssl) + "../../../../images/" + name;
}

function buildExtrasLink(name, ssl) {
	return findBaseURL(ssl) + "../../../../extras/" + name;
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

	string += _appendParam(ORIGLOC,	PARAM_ORIGLOC, args, getOrigLocation, string);
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
	string += _appendParam(TOPRANK,	PARAM_TOPRANK, args, getTopRank, string);
	string += _appendParam(AUTHTIME,	PARAM_AUTHTIME, args, getAuthtime, string);
	string += _appendParam(ADVTERM,	PARAM_ADVTERM, args, getAdvTerm, string);
	string += _appendParam(ADVTYPE,	PARAM_ADVTYPE, args, getAdvType, string);

	return string.replace(/\&$/,'').replace(/\?\&/,"?");	
}

function _appendParam( fieldVar, fieldName, overrideArgs, getFunc, string ) {
	var ret = "";
	if( fieldVar != null && overrideArgs[fieldName] == null ) 
		ret = "&" + fieldName + "=" + encodeURIComponent(getFunc());
	return ret;
}

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
function grabUser(ses, force) {

	if(!ses && isXUL()) ses = xulG['authtoken'];
	if(!ses) ses = cookieManager.read(COOKIE_SES);
	if(!ses) return false;

	if(!force) 
		if(G.user && G.user.session == ses)
			return G.user;

	/* first make sure the session is valid */
	var request = new Request(FETCH_SESSION, ses, 1 );
	request.send(true);
	var user = request.result();

	if(checkILSEvent(user)) {
		__ilsEvent = user;
		doLogout();
		return false; /* unable to grab the session */
	}

	if( !(typeof user == 'object' && user._isfieldmapper) ) {
		doLogout();
		return false;
	}

	G.user = user;
	G.user.fleshed = false;
	G.user.session = ses;
	cookieManager.write(COOKIE_SES, ses, '+1y');

	grabUserPrefs();
	if(G.user.prefs['opac.hits_per_page'])
		COUNT = parseInt(G.user.prefs['opac.hits_per_page']);

	var at = getAuthtime();
	if(isXUL()) at = xulG['authtime'];

	new AuthTimer(at).run(); /* needs debugging... */

	return G.user;
}


/* sets the 'prefs' field of the user object to their preferences 
	and returns the preferences */
function grabUserPrefs(user, force) {
	if(user == null) user = G.user;
	if(!force && user.prefs) return user.prefs;	
	var req = new Request(FETCH_USER_PREFS, user.session, user.id());
	req.send(true);
	user.prefs = req.result();
	return user.prefs;
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
		cookieManager.remove(COOKIE_SES);
	}

	G.user.session = ses;
	G.user.fleshed = true;

	cookieManager.write(COOKIE_SES, ses, '+1y'); /*  update the cookie */
	return G.user;
}

function checkUserSkin(new_skin) {

	return; /* XXX do some debugging with this... */

	var user_skin = getSkin();
	var cur_skin = grabSkinFromURL();

	if(new_skin) user_skin = new_skin;

	if(!user_skin) {

		if(grabUser()) {
			if(grabUserPrefs()) {
				user_skin = G.user.prefs["opac.skin"];
				cookieManager.write( COOKIE_SKIN, user_skin, '+1y' );
			}
		}
	}

	if(!user_skin) return;

	if( cur_skin != user_skin ) {
		var url = buildOPACLink();
		goTo(url.replace(cur_skin, user_skin));
	}
}

function updateUserSetting(setting, value, user) {
	if(user == null) user = G.user;
	var a = {};
	a[setting] = value;
	var req = new Request( UPDATE_USER_PREFS, user.session, a );
	req.send(true);
	return req.result();
}

function commitUserPrefs() {
	var req = new Request( 
		UPDATE_USER_PREFS, G.user.session, null, G.user.prefs );
	req.send(true);
	return req.result();
}

function grabSkinFromURL() {
	var path = findBasePath();
	path = path.replace("/xml/", "");
	var skin = "";
	for( var i = path.length - 1; i >= 0; i-- ) {
		var ch = path.charAt(i);
		if(ch == "/") break;
		skin += ch;
	}

	var skin2 = "";
	for( i = skin.length - 1; i >= 0; i--)
		skin2 += skin.charAt(i);

	return skin2;
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
		uname, hex_md5(seed + hex_md5(passwd)), "opac", getOrigLocation());


   auth_request.send(true);
   var auth_result = auth_request.result();

	var code = checkILSEvent(auth_result);
	if(code) { alertILSEvent(code); return null; }

	AUTHTIME = parseInt(auth_result.payload.authtime);
	var u = grabUser(auth_result.payload.authtoken, true);
	if(u) runEvt( "common", "locationChanged", u.home_ou(), findOrgDepth(u.home_ou()) );

	checkUserSkin();

	return u;
}

function doLogout(noredirect) {

	/* be nice and delete the session from the server */
	if(G.user && G.user.session) { 
		var req = new Request(LOGIN_DELETE, G.user.session);
      req.send(true);
		try { req.result(); } catch(E){}
    }

	G.user = null;
	cookieManager.remove(COOKIE_SES);
	cookieManager.remove(COOKIE_SKIN);
	checkUserSkin("default");
	COUNT = 10;

	var args = {};
	args[PARAM_TERM] = "";
	args[PARAM_LOCATION] = globalOrgTree.id();
	args[PARAM_DEPTH] = findOrgDepth(globalOrgTree);
	args.page = "home";

	var nored = false;
	try{ if(isFrontPage) nored = true; } catch(e){nored = false;}
	if(!nored) goTo(buildOPACLink(args));
}


function hideMe(obj) { addCSSClass(obj, config.css.hide_me); } 
function unHideMe(obj) { removeCSSClass(obj, config.css.hide_me); }


/* ----------------------------------------------------------------------- */
/* build the org tree */
/* ----------------------------------------------------------------------- */
function drawOrgTree() {
	//setTimeout( 'buildOrgSelector(G.ui.common.org_tree, orgTreeSelector);', 10 );
	setTimeout( 'buildOrgSelector(G.ui.common.org_tree, orgTreeSelector);', 1 );
}
	
var orgTreeSelector;
function buildOrgSelector(node) {
	var tree = new SlimTree(node,'orgTreeSelector');
	orgTreeSelector = tree;
	for( var i in orgArraySearcher ) { 
		var node = orgArraySearcher[i];
		if( node == null ) continue;
		if(node.parent_ou() == null)
			tree.addNode(node.id(), -1, node.name(), 
				"javascript:orgSelect(" + node.id() + ");", node.name());
		else {
			tree.addNode(node.id(), findOrgUnit(node.parent_ou()).id(), node.name(), 
				"javascript:orgSelect(" + node.id() + ");", node.name());
		}
	}
	hideMe($('org_loading_div'));
	unHideMe($('org_selector_tip'));
	return tree;
}

function orgSelect(id) {
	showCanvas();
	runEvt("common", "locationChanged", id, findOrgDepth(id) );

	removeChildren(G.ui.common.now_searching);
	G.ui.common.now_searching.appendChild(text(findOrgUnit(id).name()));
}

var fontCookie = new HTTP.Cookies();
function setFontSize(size) {
	scaleFonts(size);
	fontCookie.write(COOKIE_FONT, size, '+1y');
}


var resourceFormats = [
   "text",
   "moving image",
   "sound recording", "software, multimedia",
   "still images",
   "cartographic",
   "mixed material",
   "notated music",
   "three dimensional object" ];


function modsFormatToMARC(format) {
   switch(format) {
      case "text":
         return "at";
      case "moving image":
         return "g";
      case "sound recording":
         return "ij";
      case "sound recording-nonmusical":
         return "i";
      case "sound recording-musical":
         return "j";
      case "software, multimedia":
         return "m";
      case "still images":
         return "k";
      case "cartographic":
         return "ef";
      case "mixed material":
         return "op";
      case "notated music":
         return "cd";
      case "three dimensional object":
         return "r";
   }
   return "at";
}


function MARCFormatToMods(format) {
   switch(format) {
      case "a":
      case "t":
         return "text";
      case "g":
         return "moving image";
      case "i":
         return "sound recording-nonmusical";
      case "j":
         return "sound recording-musical";
      case "m":
         return "software, multimedia";
      case "k":
         return "still images";
      case "e":
      case "f":
         return "cartographic";
      case "o":
      case "p":
         return "mixed material";
      case "c":
      case "d":
         return "notated music";
      case "r":
         return "three dimensional object";
   }
   return "text";
}

function setResourcePic( img, resource ) {
	img.setAttribute( "src", "../../../../images/tor/" + resource + ".jpg");
	img.title = resource;
}



function msg( text ) {
	try { alert( text ); } catch(e) {}
}

function findRecord(id,type) {
	try {
		for( var i = 0; i != recordsCache.length; i++ ) {
			var rec = recordsCache[i];
			if( rec && rec.doc_id() == id ) return rec;
		}
	} catch(E){}
	var meth = FETCH_RMODS
	if(type == 'M') meth = FETCH_MRMODS;
	var req = new Request(meth, id);
	req.send(true);
	return req.result();
}

function Timer(name, node){
	this.name = name;
	this.count = 1;
	this.node = node;
}
Timer.prototype.start = 
	function(){_timerRun(this.name);}
Timer.prototype.stop = 
	function(){this.done = true;}
function _timerRun(tname) {
	var _t;
	eval('_t='+tname);
	if(_t.done) return;
	if(_t.count > 100) return;
	var str = ' . ';
	if( (_t.count % 5) == 0 ) 
		str = _t.count / 5;
	_t.node.appendChild(text(str));
	setTimeout("_timerRun('"+tname+"');", 200);
	_t.count++;
}

function checkILSEvent(obj) {
	if( obj.ilsevent != null && obj.ilsevent != 0 )
		return parseInt(obj.ilsevent);
	return null;
}
function alertILSEvent(code, msg) {
   if(!msg) msg = "";
	alert( msg + '\n' + $('ilsevent.' + code).innerHTML );
}


var __authTimer;
function AuthTimer(time) { 
	this.time = (time - LOGOUT_WARNING_TIME) * 1000; 
	__authTimer = this;
}

AuthTimer.prototype.run = function() {
	setTimeout('_authTimerAlert()', this.time);
}

function _authTimerAlert() {
	alert( $('auth_session_expiring').innerHTML );
	if(!grabUser(null, true)) doLogout();
}


function grabUserByBarcode( authtoken, barcode ) {
	var req = new Request( FETCH_USER_BYBARCODE, authtoken, barcode );
	req.send(true);
	return req.result();
}


function goHome() {
	goTo(buildOPACLink({page:HOME}));
}




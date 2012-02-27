/* - Request ------------------------------------------------------------- */


/* define it again here for pages that don't load RemoteRequest */
function isXUL() {
    if(location.protocol == 'chrome:' || location.protocol == 'oils:') return true;
    try { if(IAMXUL) return true;}catch(e){return false;};
}


var __ilsEvent; /* the last event the occurred */

var DEBUGSLIM;
function Request(type) {

	var s = type.split(":");
	if(s[2] == "1" && isXUL()) s[1] += ".staff";
	this.request = new RemoteRequest(s[0], s[1]);
	var p = [];

	if(isXUL()) {
		if(!location.href.match(/^https:/) && !location.href.match(/^oils:/))
			this.request.setSecure(false);

	} else {

		if( G.user && G.user.session ) {
			/* if the user is logged in, all activity resets the timeout 
				This is not entirely accurate in the sense that not all 
				requests will reset the server timeout - this should
				get close enough, however.
			*/
			var at = getAuthtime();
			if(at) new AuthTimer(at).run(); 
		}
	}

	for( var x = 1; x!= arguments.length; x++ ) {
		p.push(arguments[x]);
		this.request.addParam(arguments[x]);
	}

	if( getDebug() ) {
		var str = "";
		for( var i = 0; i != p.length; i++ ) {
			if( i > 0 ) str += ", "
			str += js2JSON(p[i]);
		}
		_debug('request ' + s[0] + ' ' + s[1] + ' ' + str );

	} else if( DEBUGSLIM ) {
		_debug('request ' + s[1]);
	}
}

Request.prototype.callback = function(cal) {this.request.setCompleteCallback(cal);}
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
	for( var p = 0; p < pages.length; p++ ) {
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

	/* handle the location var */
	var org;
	var loc = cgi.param(PARAM_LOCATION);
	var lasso = cgi.param(PARAM_LASSO);

    if ( lasso ) {
		lasso = findOrgLasso( lasso );
		LASSO = lasso ? lasso.id() : null;
	}

    if (loc) {
		org = findOrgUnit(loc);
		LOCATION = org ? org.id() : null;

		if ( !LOCATION ){
			org = findOrgUnit(loc);
			LOCATION = org ? org.id() : null;
		}
    }

	org = null;
	loc = cgi.param(PARAM_ORIGLOC);
	if( loc ) {
		org = findOrgUnit(loc);
		if(!org) org = findOrgUnitSN(loc);
	}
	ORIGLOC = (org) ? org.id() : null;


	DEPTH = parseInt(cgi.param(PARAM_DEPTH));
	if(isNaN(DEPTH)) DEPTH = null;


	FACET		= cgi.param(PARAM_FACET);
	TERM		= cgi.param(PARAM_TERM);
	STYPE		= cgi.param(PARAM_STYPE);
	FORM		= cgi.param(PARAM_FORM);
	//DEPTH		= parseInt(cgi.param(PARAM_DEPTH));
	OFFSET	= parseInt(cgi.param(PARAM_OFFSET));
	COUNT		= parseInt(cgi.param(PARAM_COUNT));
	HITCOUNT	= parseInt(cgi.param(PARAM_HITCOUNT));
	MRID		= parseInt(cgi.param(PARAM_MRID));
	RID		= parseInt(cgi.param(PARAM_RID));
	AUTHTIME	= parseInt(cgi.param(PARAM_AUTHTIME));
	ADVTERM	= cgi.param(PARAM_ADVTERM);
	ADVTYPE	= cgi.param(PARAM_ADVTYPE);
	RTYPE		= cgi.param(PARAM_RTYPE);
	SORT		= cgi.param(PARAM_SORT);
	SORT_DIR	= cgi.param(PARAM_SORT_DIR);
	DEBUG		= cgi.param(PARAM_DEBUG);
	CALLNUM	= cgi.param(PARAM_CN);
	LITFORM	= cgi.param(PARAM_LITFORM);
	ITEMFORM	= cgi.param(PARAM_ITEMFORM);
	ITEMTYPE	= cgi.param(PARAM_ITEMTYPE);
	BIBLEVEL	= cgi.param(PARAM_BIBLEVEL);
	AUDIENCE	= cgi.param(PARAM_AUDIENCE);
	SEARCHES = cgi.param(PARAM_SEARCHES);
	LANGUAGE	= cgi.param(PARAM_LANGUAGE);
	TFORM		= cgi.param(PARAM_TFORM);
	RDEPTH	= cgi.param(PARAM_RDEPTH);
    AVAIL   = cgi.param(PARAM_AVAIL);
    COPYLOCS   = cgi.param(PARAM_COPYLOCS);
    PUBD_BEFORE = cgi.param(PARAM_PUBD_BEFORE);
    PUBD_AFTER = cgi.param(PARAM_PUBD_AFTER);
    PUBD_BETWEEN = cgi.param(PARAM_PUBD_BETWEEN);
    PUBD_DURING = cgi.param(PARAM_PUBD_DURING);

    
	/* set up some sane defaults */
	//if(isNaN(DEPTH))	DEPTH		= 0;
	if(isNaN(RDEPTH))	RDEPTH	= 0;
	if(isNaN(OFFSET))	OFFSET	= 0;
	if(isNaN(COUNT))	COUNT		= 10;
	if(isNaN(HITCOUNT))	HITCOUNT	= 0;
	if(isNaN(MRID))		MRID		= 0;
	if(isNaN(RID))		RID		= 0;
	if(isNaN(ORIGLOC))	ORIGLOC	= 0; /* so we know it hasn't been set */
	if(isNaN(AUTHTIME))	AUTHTIME	= 0;
	if(ADVTERM==null)	ADVTERM	= "";
    if(isNaN(AVAIL))    AVAIL = 0;
}

function clearSearchParams() {
	TERM        = null;
	STYPE       = null;
	FORM        = null;
	OFFSET      = 0;
	HITCOUNT    = 0;  
	ADVTERM     = null;
	ADVTYPE     = null;
	MRID        = null;
	RID         = null;
	RTYPE       = null;
	SORT        = null;
	SORT_DIR    = null;
	RLIST       = null;
	CALLNUM	    = null;
	LITFORM	    = null;
	ITEMFORM    = null;
	ITEMTYPE    = null;
	BIBLEVEL    = null;
	AUDIENCE    = null;
	SEARCHES    = null;
	LANGUAGE    = null;
	RDEPTH      = null;
    AVAIL       = null;
    COPYLOCS    = null;
    PUBD_BEFORE = null;
    PUBD_AFTER  = null;
    PUBD_BETWEEN = null;
    PUBD_DURING = null;
}


function initCookies() {
    dojo.require('dojo.cookie');
	FONTSIZE = "regular";
	var font = dojo.cookie(COOKIE_FONT);
	scaleFonts(font);
	if(font) FONTSIZE = font;
	SKIN = dojo.cookie(COOKIE_SKIN);
    if(findCurrentPage() == HOME)
        dojo.cookie(COOKIE_SEARCH,null,{'expires':-1});
}

/* URL param accessors */
function getTerm(){return TERM;}
function getFacet(){return FACET;}
function getStype(){return STYPE;}
function getLocation(){return LOCATION;}
function getLasso(){return LASSO;}
function getDepth(){return DEPTH;}
function getForm(){return FORM;}
function getTform(){return TFORM;}
function getOffset(){return OFFSET;}
function getDisplayCount(){return COUNT;}
function getHitCount(){return HITCOUNT;}
function getMrid(){return MRID;};
function getRid(){return RID;};
function getOrigLocation(){return ORIGLOC;}
function getAuthtime() { return AUTHTIME; }
function getSearchBarExtras(){return SBEXTRAS;}
function getFontSize(){return FONTSIZE;};
function getSkin(){return SKIN;};
function getAdvTerm(){return ADVTERM;}
function getAdvType(){return ADVTYPE;}
function getRtype(){return RTYPE;}
function getSort(){return SORT;}
function getSortDir(){return SORT_DIR;}
function getDebug(){return DEBUG;}
function getCallnumber() { return CALLNUM; }
function getLitForm() { return LITFORM; }
function getItemForm() { return ITEMFORM; }
function getItemType() { return ITEMTYPE; }
function getBibLevel() { return BIBLEVEL; }
function getAudience() { return AUDIENCE; }
function getSearches() { return SEARCHES; }
function getLanguage() { return LANGUAGE; }
function getRdepth() { return RDEPTH; }
function getAvail() { return AVAIL; }
function getCopyLocs() { return COPYLOCS; }
function getPubdBefore() { return PUBD_BEFORE; }
function getPubdAfter() { return PUBD_AFTER; }
function getPubdBetween() { return PUBD_BETWEEN; }
function getPubdDuring() { return PUBD_DURING; }


function findBasePath() {
	var path = location.pathname;
	if(!path.match(/.*\.xml$/)) path += "index.xml"; 
	var idx = path.indexOf(config.page[findCurrentPage()]);
	return path.substring(0, idx);
}

function findBaseURL(ssl) {
	var path = findBasePath();
	var proto = (ssl) ? "https:" : "http:";
	if(ssl && location.protocol == 'oils:') proto = 'oils:';

	/* strip port numbers.  This is necessary for browsers that
	send an explicit  <host>:80, 443 - explicit ports
	break links that need to change ports (e.g. http -> https) */
	var h = location.host.replace(/:.*/,''); 

	return proto + "//" + h + path;
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

var consoleService;
function _debug(str) { 
	try { dump('dbg: ' + str + '\n'); } catch(e) {} 

	/* potentially useful, but usually just annoying */
	/*
	if(!IE) {
		if(!consoleService) {
			try {
				this.consoleService = Components.classes['@mozilla.org/consoleservice;1']
					.getService(Components.interfaces.nsIConsoleService);
			} catch(e) {}
		}
	
		try {
			if(consoleService) {
				consoleService.logStringMessage(str + '\n');
			}
		} catch(e){}
	}
	*/
}

var forceLoginSSL; // set via Apache env variable
function  buildOPACLink(args, slim, ssl) {

	if(!args) args = {};
	var string = "";

    if( ssl == undefined && (
            location.protocol == 'https:' || location.protocol == 'oils:' ||
            (forceLoginSSL && G.user && G.user.session))) {
        ssl = true;
    }

	if(!slim) {
		string = findBaseURL(ssl);
		if(args.page) string += config.page[args.page];
		else string += config.page[findCurrentPage()];
	}

	/* this may seem unnecessary.. safety precaution for now */
	/*
	if( args[PARAM_DEPTH] == null )
		args[PARAM_DEPTH] = getDepth();
		*/

	string += "?";

	for( var x in args ) {
		var v = args[x];
		if(x == "page" || v == null || v == undefined || v+'' == 'NaN' ) continue;
		if(x == PARAM_OFFSET && v == 0) continue;
		if(x == PARAM_COUNT && v == 10) continue;
		if(x == PARAM_FORM && v == 'all' ) continue;
		if( instanceOf(v, Array) && v.length ) {
			for( var i = 0; i < v.length; i++ ) {
				string += "&" + x + "=" + encodeURIComponent(v[i]);
			}
		} else {
			string += "&" + x + "=" + encodeURIComponent(v);
		}
	}

	if(getDebug())
		string += _appendParam(DEBUG,		PARAM_DEBUG, args, getDebug, string);
	if(getOrigLocation() != 1) 
		string += _appendParam(ORIGLOC,	PARAM_ORIGLOC, args, getOrigLocation, string);
	if(getTerm()) 
		string += _appendParam(TERM,		PARAM_TERM, args, getTerm, string);
	if(getFacet()) 
		string += _appendParam(FACET,		PARAM_FACET, args, getFacet, string);
	if(getStype()) 
		string += _appendParam(STYPE,		PARAM_STYPE, args, getStype, string);
	if(getLocation() != 1) 
		string += _appendParam(LOCATION, PARAM_LOCATION, args, getLocation, string);
	if(getLasso() != null) 
		string += _appendParam(LASSO, PARAM_LASSO, args, getLasso, string);
	if(getDepth() != null) 
		string += _appendParam(DEPTH,		PARAM_DEPTH, args, getDepth, string);
	if(getForm() && (getForm() != 'all') ) 
		string += _appendParam(FORM,		PARAM_FORM, args, getForm, string);
	if(getTform() && (getTform() != 'all') ) 
		string += _appendParam(TFORM,		PARAM_TFORM, args, getTform, string);
	if(getOffset() != 0) 
		string += _appendParam(OFFSET,	PARAM_OFFSET, args, getOffset, string);
	if(getDisplayCount() != 10) 
		string += _appendParam(COUNT,		PARAM_COUNT, args, getDisplayCount, string);
	if(getHitCount()) 
		string += _appendParam(HITCOUNT, PARAM_HITCOUNT, args, getHitCount, string);
	if(getMrid())
		string += _appendParam(MRID,		PARAM_MRID, args, getMrid, string);
	if(getRid())
		string += _appendParam(RID,		PARAM_RID, args, getRid, string);
	if(getAuthtime())
		string += _appendParam(AUTHTIME,	PARAM_AUTHTIME, args, getAuthtime, string);
	if(getAdvTerm())
		string += _appendParam(ADVTERM,	PARAM_ADVTERM, args, getAdvTerm, string);
	if(getAdvType())
		string += _appendParam(ADVTYPE,	PARAM_ADVTYPE, args, getAdvType, string);
	if(getRtype())
		string += _appendParam(RTYPE,		PARAM_RTYPE, args, getRtype, string);
	if(getItemForm())
		string += _appendParam(ITEMFORM,	PARAM_ITEMFORM, args, getItemForm, string);
	if(getItemType())
		string += _appendParam(ITEMTYPE,	PARAM_ITEMTYPE, args, getItemType, string);
	if(getBibLevel())
		string += _appendParam(BIBLEVEL,	PARAM_BIBLEVEL, args, getBibLevel, string);
	if(getLitForm())
		string += _appendParam(LITFORM,	PARAM_LITFORM, args, getLitForm, string);
	if(getAudience())
		string += _appendParam(AUDIENCE,	PARAM_AUDIENCE, args, getAudience, string);
	if(getSearches())
		string += _appendParam(SEARCHES,	PARAM_SEARCHES, args, getSearches, string);
	if(getLanguage())
		string += _appendParam(LANGUAGE,	PARAM_LANGUAGE, args, getLanguage, string);
	if(getRdepth() != null)
		string += _appendParam(RDEPTH,	PARAM_RDEPTH, args, getRdepth, string);
	if(getSort() != null)
		string += _appendParam(SORT,	PARAM_SORT, args, getSort, string);
	if(getSortDir() != null)
		string += _appendParam(SORT_DIR,	PARAM_SORT_DIR, args, getSortDir, string);
	if(getAvail())
		string += _appendParam(AVAIL, PARAM_AVAIL, args, getAvail, string);
	if(getCopyLocs())
		string += _appendParam(COPYLOCS, PARAM_COPYLOCS, args, getCopyLocs, string);
    if(getPubdBefore())
		string += _appendParam(PUBD_BEFORE, PARAM_PUBD_BEFORE, args, getPubdBefore, string);
    if(getPubdAfter())
		string += _appendParam(PUBD_AFTER, PARAM_PUBD_AFTER, args, getPubdAfter, string);
    if(getPubdBetween())
		string += _appendParam(PUBD_BETWEEN, PARAM_PUBD_BETWEEN, args, getPubdBetween, string);
    if(getPubdDuring())
		string += _appendParam(PUBD_DURING, PARAM_PUBD_DURING, args, getPubdDuring, string);


	return string.replace(/\&$/,'').replace(/\?\&/,"?");	
}

var xx = 1;
function _appendParam( fieldVar, fieldName, overrideArgs, getFunc, string ) {

	var ret = "";

	if(	fieldVar != null && 
			(fieldVar +'' != 'NaN') && 
			overrideArgs[fieldName] == null &&
			getFunc() != null &&
			getFunc()+'' != '' ) {

		ret = "&" + fieldName + "=" + encodeURIComponent(getFunc());
	}

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
	args[PARAM_RTYPE] = RTYPE_MRID;
    var linkText = link.innerHTML; // IE
	link.setAttribute("href", buildOPACLink(args));
    link.innerHTML = linkText; // IE
}

function buildTitleDetailLink(rec, link) {
	if(!rec) return;
	link.appendChild(text(normalize(truncate(rec.title(), 65))));
	var args = {};
	args.page = RDETAIL;
	args[PARAM_RID] = rec.doc_id();
    // in IE, if the link text contains a '@', it replaces the innerHTML text 
    // with the value of the href attribute.  Wait, what?  Yes.  Capture the
    // innerHTML and put it back into place after the href is set
    var linkText = link.innerHTML; // IE
	link.setAttribute("href", buildOPACLink(args));
    link.innerHTML = linkText; // IE
}

/* 'type' is one of STYPE_AUTHOR, STYPE_SUBJECT, ... found in config.js 
	'trunc' is the number of characters to show in the string, defaults to 65 */
function buildSearchLink(type, string, linknode, trunc) {
	if(!trunc) trunc = 65;
	var args = {};
	if( SHOW_MR_DEFAULT || findCurrentPage() == MRESULT ) {
		args.page = MRESULT;
	} else {
		args.page = RRESULT;
		args[PARAM_RTYPE] = type;
	}
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = string;
	args[PARAM_STYPE] = type;
	linknode.appendChild(text(normalize(truncate(string, trunc))));
	linknode.setAttribute("href", buildOPACLink(args));
}

function setSessionCookie(ses) {
	dojo.cookie(COOKIE_SES, ses, {'secure':'true'});
}



/* ----------------------------------------------------------------------- */
/* user session handling */
/* ----------------------------------------------------------------------- */
/* session is the login session.  If no session is provided, we attempt
	to find one in the cookies.  If 'force' is true we retrieve the 
	user from the server even if there is already a global user present.
	if ses != G.user.session, we also force a grab */
function grabUser(ses, force) {

    _debug("grabUser auth token = " + ses);
	if(!ses && isXUL()) {
		stash = fetchXULStash();
		ses = stash.session.key
		_debug("stash auth token = " + ses);
	}

	if(!ses) {
		ses = dojo.cookie(COOKIE_SES);
		/* https cookies don't show up in http servers.. */
		_debug("cookie auth token = " + ses);
	}

	if(!ses) return false;

	if(!force) 
		if(G.user && G.user.session == ses)
			return G.user;

	/* first make sure the session is valid */
	var request = new Request(FETCH_SESSION, ses);
	request.request.alertEvent = false;
	request.send(true);
	var user = request.result();

	if(!user || user.textcode == 'NO_SESSION') {

        if(isXUL()) {
            dojo.require('openils.XUL');
            dump('getNewSession in opac_utils.js\n');
            openils.XUL.getNewSession( 
                function(success, authtoken) { 
                    if(success) {
                        ses = authtoken;
                        var request = new Request(FETCH_SESSION, ses);
                        request.request.alertEvent = false;
                        request.send(true);
                        user = request.result();
                    }
                }
            );
        }

	    if(!user || user.textcode == 'NO_SESSION') {
		    doLogout();
		    return false; /* unable to grab the session */
        }
	}

	if( !(typeof user == 'object' && user._isfieldmapper) ) {
		doLogout();
		return false;
	}

	G.user = user;
	G.user.fleshed = false;
	G.user.session = ses;
	setSessionCookie(ses);

	grabUserPrefs();
	if(G.user.prefs['opac.hits_per_page'])
		COUNT = parseInt(G.user.prefs['opac.hits_per_page']);

	if(G.user.prefs[PREF_DEF_FONT]) 
		setFontSize(G.user.prefs[PREF_DEF_FONT]);

	var at = getAuthtime();
	//if(isXUL()) at = xulG['authtime'];

	if(at && !isXUL()) new AuthTimer(at).run(); 
	return G.user;
}


/* sets the 'prefs' field of the user object to their preferences 
	and returns the preferences */
function grabUserPrefs(user, force) {
	if(user == null) user = G.user;
	if(!force && user.prefs) return user.prefs;	
	var req = new Request(FETCH_USER_PREFS, G.user.session, user.id());
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
		dojo.cookie(COOKIE_SES,null,{'expires':-1});
		G.user = null; return false; 
	}

	G.user.session = ses;
	G.user.fleshed = true;

	setSessionCookie(ses);
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
				dojo.cookie( COOKIE_SKIN, user_skin, { 'expires' : 365 } );
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
function doLogin(suppressEvents) {

	abortAllRequests();

	var auth_proxy_enabled = false;
	var auth_proxy_enabled_request = new Request( AUTH_PROXY_ENABLED );
	auth_proxy_enabled_request.request.alertEvent = false;
	auth_proxy_enabled_request.send(true);
	if (auth_proxy_enabled_request.result() == 1) {
		auth_proxy_enabled = true;
	}

	var uname = G.ui.login.username.value;
	var passwd = G.ui.login.password.value;

	var args = {
		type		: "opac", 
		org		: getOrigLocation(),
		agent : 'opac'
	};

	r = fetchOrgSettingDefault(globalOrgTree.id(), 'opac.barcode_regex');
	if(r) REGEX_BARCODE = new RegExp(r);

	if( uname.match(REGEX_BARCODE) ) args.barcode = uname;
	else args.username = uname;

	var auth_request;
	if (!auth_proxy_enabled) {
		var init_request = new Request( LOGIN_INIT, uname );
		init_request.send(true);
		var seed = init_request.result();

		if( ! seed || seed == '0') {
			alert( "Error Communicating with Authentication Server" );
			return null;
		}

		args.password = hex_md5(seed + hex_md5(passwd));
		auth_request = new Request( LOGIN_COMPLETE, args );
	} else {
		args.password = passwd;
		auth_request = new Request( AUTH_PROXY_LOGIN, args );
	}

	auth_request.request.alertEvent = false;
   auth_request.send(true);
   var auth_result = auth_request.result();

	if(!auth_result) {
		alertId('patron_login_failed');
		return null;
	}

	if( checkILSEvent(auth_result) ) {

		if( auth_result.textcode == 'PATRON_INACTIVE' ) {
			alertId('patron_inactive_alert');
			return;
		}

		if( auth_result.textcode == 'PATRON_CARD_INACTIVE' ) {
			alertId('patron_card_inactive_alert');
			return;
		}

		if( auth_result.textcode == 'LOGIN_FAILED' || 
				auth_result.textcode == 'PERM_FAILURE' ) {
			alertId('patron_login_failed');
			return;
		}
	}


	AUTHTIME = parseInt(auth_result.payload.authtime);
	var u = grabUser(auth_result.payload.authtoken, true);
	if(u && ! suppressEvents) 
		runEvt( "common", "locationChanged", u.ws_ou(), findOrgDepth(u.ws_ou()) );

	checkUserSkin();

	return u;
}

function doLogout() {

	/* cancel everything else */
	abortAllRequests();

	/* be nice and delete the session from the server */
	if(G.user && G.user.session) { 
		var req = new Request(LOGIN_DELETE, G.user.session);
      req.send(true);
		try { req.result(); } catch(E){}
    }

	G.user = null;

	/* remove any cached data */
    dojo.require('dojo.cookie');
    dojo.cookie(COOKIE_SES, null, {expires:-1});
    dojo.cookie(COOKIE_RIDS, null, {expires:-1});
    dojo.cookie(COOKIE_SKIN, null, {expires:-1});
    dojo.cookie(COOKIE_SEARCH, null, {expires:-1});


	checkUserSkin("default");
	COUNT = 10;


	var args = {};
	args[PARAM_TERM] = "";
	args[PARAM_LOCATION] = getOrigLocation();
    args[PARAM_DEPTH] = findOrgDepth(getOrigLocation() || globalOrgTree);
	args.page = "home";

	
	var nored = false;
	try{ if(isFrontPage) nored = true; } catch(e){nored = false;}
	if(!nored) goTo(buildOPACLink(args, false, false));
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

var checkOrgHiding_cached = false;
var checkOrgHiding_cached_context_org;
var checkOrgHiding_cached_depth;
function checkOrgHiding() {
    if (isXUL()) {
        return false; // disable org hiding for staff client
    }
    var context_org = getOrigLocation() || globalOrgTree.id();
    var depth;
    if (checkOrgHiding_cached) {
        if (checkOrgHiding_cached_context_org != context_org) {
            checkOrgHiding_cached_context_org = context_org;
            checkOrgHiding_cached_depth = undefined;
            checkOrgHiding_cached = false;
        } else {
            depth = checkOrgHiding_cached_depth;
        }
    } else {
        depth = fetchOrgSettingDefault( context_org, 'opac.org_unit_hiding.depth');
        checkOrgHiding_cached_depth = depth;
        checkOrgHiding_cached_context_org = context_org;
        checkOrgHiding_cached = true;
    }
    if ( findOrgDepth( context_org ) < depth ) {
        return false; // disable org hiding if Original Location doesn't make sense with setting depth (avoids disjointed org selectors)
    }
    if (depth) {
        return { 'org' : findOrgUnit(context_org), 'depth' : depth };
    } else {
        return false;
    }
}

var orgTreeSelector;
function buildOrgSelector(node) {
	var tree = new SlimTree(node,'orgTreeSelector');
	orgTreeSelector = tree;
	var orgHiding = checkOrgHiding();
	for (var i = 0; i < orgArraySearcherOrder.length; i++) {
		var node = orgArraySearcher[orgArraySearcherOrder[i]];
		if( node == null ) continue;
		if(!isXUL() && !isTrue(node.opac_visible())) continue; 
		if (orgHiding) {
			if ( ! orgIsMine( orgHiding.org, node, orgHiding.depth ) ) {
				continue;
			}
		}
		if(node.parent_ou() == null) {
			tree.addNode(node.id(), -1, node.name(), 
				"javascript:orgSelect(" + node.id() + ");", node.name());
		} else {
			if (orgHiding && orgHiding.depth == findOrgDepth(node)) {
				tree.addNode(node.id(), -1, node.name(), 
					"javascript:orgSelect(" + node.id() + ");", node.name());
			} else {
				tree.addNode(node.id(), node.parent_ou(), node.name(), 
					"javascript:orgSelect(" + node.id() + ");", node.name());
			}
		}
	}
	hideMe($('org_loading_div'));
	unHideMe($('org_selector_tip'));
	return tree;
}

function orgSelect(id) {
	showCanvas();
	runEvt("common", "locationChanged", id, findOrgDepth(id) );


	var loc = findOrgLasso(getLasso());
	if (!loc) loc = findOrgUnit(id);

	removeChildren(G.ui.common.now_searching);
	G.ui.common.now_searching.appendChild(text(loc.name()));
}

function setFontSize(size) {
	scaleFonts(size);
	dojo.cookie(COOKIE_FONT, size, { 'expires' : 365});
}

var resourceFormats = [
   "text",
   "moving image",
   "sound recording", "software, multimedia",
   "still image",
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
      case "still image":
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
         return "still image";
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

function MARCTypeToFriendly(format) {
	var words = $('format_words');
	switch(format) {
		case 'a' :
		case 't' : return $n(words, 'at').innerHTML;
		default:
			var node = $n(words,format);
			if( node ) return node.innerHTML;
	}
	return "";
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
	req.request.alertEvent = false;
	req.send(true);
	var res = req.result();
	if( checkILSEvent(res) ) return null; 
	return res;
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
	if (obj && typeof obj == 'object' && typeof obj.ilsevent != 'undefined') {
        if (obj.ilsevent === '') {
            return true;
        } else if ( obj.ilsevent != null && obj.ilsevent != 0 ) {
            return parseInt(obj.ilsevent);
        }
    }
	return null;
}


function alertILSEvent(evt, msg) {
   if(!msg) msg = "";
	if(msg)
		alert(msg +'\n' + evt.textcode + '\n' + evt.desc );
	else 
		alert(evt.textcode + '\n' + evt.desc );
}


var __authTimer;
function AuthTimer(time) { 
	this.time = (time - LOGOUT_WARNING_TIME) * 1000; 
	if(__authTimer) 
		try {clearTimeout(__authTimer.id)} catch(e){}
	__authTimer = this;
}

AuthTimer.prototype.run = function() {
	this.id = setTimeout('_authTimerAlert()', this.time);
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


function buildOrgSel(selector, org, offset, namecol) {
    if(!namecol) namecol = 'name';
    if(!isXUL() && !isTrue(org.opac_visible())) return;
	insertSelectorVal( selector, -1, 
		org[namecol](), org.id(), null, findOrgDepth(org) - offset );
    var kids = org.children();
    if (kids) {
	    for( var c = 0; c < kids.length; c++ )
		    buildOrgSel( selector, kids[c], offset, namecol);
    }
}

function buildMergedOrgSel(selector, org_list, offset, namecol) {
    if(!namecol) namecol = 'name';
    for(var i = 0; i < org_list.length; i++) {
        var org = findOrgUnit(org_list[i]);
    	insertSelectorVal( selector, -1, 
		    org[namecol](), org.id(), null, findOrgDepth(org) - offset );
        var kids = org.children();
        if (kids) {
	        for( var c = 0; c < kids.length; c++ )
		        buildOrgSel( selector, kids[c], offset, namecol);
        }
    }
}


function parseForm(form) {
	if(!form) return {};

	var it = form.replace(/-\w+$/,"");
	var itf = null;
	var item_form;
	var item_type;

	if(form.match(/-/)) itf = form.replace(/^\w+-/,"");

	if(it) {
		item_type = [];
		for( var i = 0; i < it.length; i++ ) 
			item_type.push( it.charAt(i) );
	}

	if(itf) {
		item_form = [];
		for( var i = 0; i < itf.length; i++ ) 
			item_form.push( itf.charAt(i) );
	}

	return {item_type: item_type, item_form:item_form};
}


function isTrue(x) { return ( x && x != "0" && !(x+'').match(/^f$/i) ); }

function fetchPermOrgs() {
	var a = []; /* Q: why does arguments come accross as an object and not an array? A: because arguments is a special object, a collection */

	for( var i = 0; i < arguments.length; i++ ) 
		a.push(arguments[i])

	var preq = new Request(FETCH_HIGHEST_PERM_ORG, 
		G.user.session, G.user.id(), a );
	preq.send(true);
	return preq.result();
}


function print_tabs(t) {
	var r = '';
	for (var j = 0; j < t; j++ ) { r = r + "  "; }
	return r;
}
function formatJSON(s) {
	var r = ''; var t = 0;
	for (var i in s) {
		if (s[i] == '{' || s[i] == '[' ) {
			r = r + s[i] + "\n" + print_tabs(++t);
		} else if (s[i] == '}' || s[i] == ']') {
			t--; r = r + "\n" + print_tabs(t) + s[i];
		} else if (s[i] == ',') {
			r = r + s[i] + "\n" + print_tabs(t);
		} else {
			r = r + s[i];
		}
	}
	return r;
}

var IAMXUL = false;
function isXUL() { return IAMXUL; }


/* - Request ------------------------------------------------------------- */
function Request(type) {
	var s = type.split(":");
	this.request = new RemoteRequest(s[0], s[1]);
	for( var x = 1; x!= arguments.length; x++ ) 
		this.request.addParam(arguments[x]);
}

Request.prototype.callback = function(cal) { this.request.setCompleteCallback(cal); }
Request.prototype.send		= function(block){this.request.send(block);}
/* ----------------------------------------------------------------------- */


/* finds the name of the current page */
function findCurrentPage() {
	for( var p in config.page ) {
		var path = location.pathname;

		if(!path.match(/.*\.xml$/))
			path += "index.xml"; /* in case they go to  / */

		if( config.page[p] == path)
			return p;
	}
	return null;
}


/* builds an opac URL.  If no page is defined, the current page is used
	if slim, then only everything after the ? is returned (no host portion)
 */
function  buildOPACLink(args, slim) {

	if(!args) args = {};

	if(!slim) {
		var string = location.protocol + "//" + location.host;
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





/* ----------------------------------------------------------------------- */
/* some useful exceptions */
function EX(message) { this.init(message); }

EX.prototype.init = function(message) {
   this.message = message;
}

EX.prototype.toString = function() {
   return "\n *** Exception Occured \n" + this.message;
}  

EXCommunication.prototype              = new EX();
EXCommunication.prototype.constructor  = EXCommunication;
EXCommunication.baseClass              = EX.prototype.constructor;

function EXCommunication(message) {
   this.init("EXCommunication: " + message);
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


function doLogin() {
}


/* ----------------------------------------------------------------------- */
/* builds a link that goes to the title listings for a metarecord */
function buildTitleLink(rec, link) {

	var t = rec.title(); 
	t = normalize(truncate(t, 65));
	link.appendChild(text(t));

	var args = {};
	args.page = RRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_MRID] = rec.doc_id();
	link.setAttribute("href", buildOPACLink(args));
}

/* builds an author search link */
function buildAuthorLink(rec, link) {

	var a = rec.author(); 
	a = normalize(truncate(a, 65));
	link.appendChild(text(a));

	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_STYPE] = "author";
	args[PARAM_TERM] = rec.author();
	link.setAttribute("href", buildOPACLink(args));

}
/* ----------------------------------------------------------------------- */







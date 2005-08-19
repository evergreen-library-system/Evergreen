/* Export some constants  ----------------------------------------------------- */

/* URL params */
var PARAM_TERM					= "term";		/* search term */
var PARAM_STYPE				= "stype";		/* search type */
var PARAM_LOCATION			= "location"	/* current location */;
var PARAM_DEPTH				= "depth";		/* search depth */
var PARAM_FORM					= "format";		/* search format */
var PARAM_OFFSET				= "offset";		/* search offset */
var PARAM_COUNT				= "count";		/* hits per page */
var PARAM_HITCOUNT			= "hitcount";	/* hits per page */
var PARAM_MRID					= "mrid";		/* metarecord id */
var PARAM_RID					= "rid";			/* record id */

/* cookies */
var COOKIE_SB = "sbe";
var COOKIE_SES = "ses";
var COOKIE_IDS	= "ids";

/* these are the actual param values - set on page load */

/* pages */
var MRESULT		= "mresult";
var RRESULT		= "rresult";
var RDETAIL		= "rdetail";
var MYOPAC		= "myopac";
var ADVANCED	= "advanced";
var HOME			= "home";

/* search type (STYPE) options */
STYPE_AUTHOR	= "author";
STYPE_TITLE		= "title";
STYPE_SUBJECT	= "subject";
STYPE_SERIES	= "series";
STYPE_KEYWORD	= "keyword";


/* container for global variables shared accross pages */
var G		= {};
G.user	= null; /* global user object */
G.ui		= {} /* cache of UI components */


/* call me after page init and I will load references 
	to all of the ui object id's defined below 
	They will be stored in G.ui.<page>.<thingy>
 */
function loadUIObjects() {
	for( var p in config.ids ) {
		G.ui[p] = {};
		for( var o in config.ids[p] ) 
			G.ui[p][o] = getId(config.ids[p][o]);
	}
}

/* try our best to free memory */
function clearUIObjects() {
	for( var p in config.ids ) {
		for( var o in config.ids[p] ) {
			if(G.ui[p][o]) {
				G.ui[p][o].onclick = null;
				G.ui[p][o].onkeydown = null;
				G.ui[p][o] = null;
			}
		}
		G.ui[p] = null;
	}
}

/* ---------------------------------------------------------------------------- 
	Set up ID's and CSS classes 
	Any new ids, css, etc. may be added by giving the unique names and putting 
	them into the correct scope 
/* ---------------------------------------------------------------------------- */

var config = {};

/* Set up the page names */
config.page = {};
config.page[HOME]			= "index.xml";
config.page[ADVANCED]	= "advanced.xml";
config.page[MRESULT]		= "mresult.xml";
config.page[RRESULT]		= "rresult.xml";
config.page[MYOPAC]		= "myopac.xml";
config.page[RDETAIL]		= "rdetail.xml";


/* set up images  */
config.images = {};
config.images.logo = "main_logo.jpg";


/* set up ID's, CSS, and node names */
config.ids				= {};
config.ids.result		= {};
config.ids.mresult	= {};
config.ids.advanced	= {};
config.ids.rresult	= {};
config.ids.myopac		= {};
config.ids.rdetail	= {};

config.css				= {};
config.css.result		= {};
config.css.mresult	= {};
config.css.advanced	= {};
config.css.rresult	= {};
config.css.myopac		= {};
config.css.rdetail	= {};

config.names			= {};
config.names.result	= {};
config.names.mresult = {};
config.names.advanced = {};
config.names.rresult = {};
config.names.myopac	= {};
config.names.rdetail = {};


/* id's shared accross skins. These *must* be defined */
config.ids.common = {};
config.ids.common.loading			= "loading_div";		
config.ids.common.canvas			= "canvas";				
config.ids.common.canvas_main		= "canvas_main";		
config.ids.common.org_tree			= "org_tree";			
config.ids.common.org_container	= "org_container";


/* shared CSS */
config.css.hide_me = "hide_me";


/* ---------------------------------------------------------------------------- */
/* These are pages that may replace the canvas */
/* ---------------------------------------------------------------------------- */
config.ids.altcanvas = {};



/* ---------------------------------------------------------------------------- */
/* Methods are defined as service:method 
	An optional 3rd component is when a method is followed by a :1, such methods
	have a staff counterpart and should have ".staff" appended to the method 
	before the method is called when in XUL mode */

var FETCH_MRCOUNT				= "open-ils.search:open-ils.search.biblio.class.count:1";
var FETCH_MRIDS				= "open-ils.search:open-ils.search.biblio.class:1";
var FETCH_MRIDS_FULL			= "open-ils.search:open-ils.search.biblio.class.full:1";
var FETCH_MRMODS				= "open-ils.search:open-ils.search.biblio.metarecord.mods_slim.retrieve";
var FETCH_MR_COPY_COUNTS	= "open-ils.search:open-ils.search.biblio.metarecord.copy_count:1";
var FETCH_RIDS					= "open-ils.search:open-ils.search.biblio.metarecord_to_records:1";
var FETCH_RMODS				= "open-ils.search:open-ils.search.biblio.record.mods_slim.retrieve";
var FETCH_R_COPY_COUNTS		= "open-ils.search:open-ils.search.biblio.record.copy_count";
var FETCH_FLESHED_USER		= "open-ils.actor:open-ils.actor.user.fleshed.retrieve";
var FETCH_SESSION				= "open-ils.auth:open-ils.auth.session.retrieve";
var LOGIN_INIT					= "open-ils.auth:open-ils.auth.authenticate.init";
var LOGIN_COMPLETE			= "open-ils.auth:open-ils.auth.authenticate.complete";
var LOGIN_DELETE				= "open-ils.auth:open-ils.auth.session.delete";
/* ---------------------------------------------------------------------------- */



/* ---------------------------------------------------------------------------- */
/* event callback functions. Other functions may be appended to these vars to
	for added functionality.  */

G.evt				= {}; /* events container */

function runEvt(scope, name, a, b, c, d, e, f, g) {
	var evt = G.evt[scope][name];
	for( var i in evt ) evt[i](a, b, c, d, e, f, g);	
}

/* creates a new event if it doesn't already exist */
function createEvt(scope, name) {
	if(!G.evt[scope]) G.evt[scope] = {};
	if(G.evt[scope][name] == null)
		G.evt[scope][name] = []; 
}

function attachEvt(scope, name, action) {
	createEvt(scope, name);
	G.evt[scope][name].push(action);
}

createEvt("common", "init");						/* f() : what happens on page init */
createEvt("common", "unload");					/* f() : what happens on window unload (clean memory, etc.)*/
createEvt("mresult", "run");						/* f() : kick of the page*/
createEvt("mresult", "idsReceived");			/* f(ids) */
createEvt("rresult", "run");						/* f() : kick of the page*/
createEvt("rresult", "idsReceived");			/* f(ids) */	

createEvt("result", "hitCountReceived");		/* f() : display hit info, pagination, etc. */
createEvt("result", "recordReceived");			/* f(mvr, pagePosition, isMr) : display the record*/
createEvt("result", "copyCountsReceived");	/* f(mvr, pagePosition, copyCountInfo) : display copy counts*/
createEvt("result", "allRecordsReceived");	/* f(mvrsArray) : add other page stuff, sidebars, etc.*/





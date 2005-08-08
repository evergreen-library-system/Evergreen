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
var PARAM_RANKS				= "hitcount";	/* hits per page */
var PARAM_MRID					= "mrid";		/* metarecord id */
var PARAM_RID					= "rid";			/* metarecord id */

/* cookies */
var COOKIE_SB = "sbe";
var COOKIE_SES = "ses";

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
				G.ui[p][o] = null;
			}
		}
		G.ui[p] = null;
	}
}



/* ---------------------------------------------------------------------------- */
/* Set up ID's and CSS classes */
/* ---------------------------------------------------------------------------- */

var config = {};
config.text = {};
config.ids = {};
config.names = {};

config.ids.common = {};
config.ids.common.loading		= "loading_div";		/* generic 'loading..' message */
config.ids.common.canvas		= "canvas";				/* outer UI canvas that holds the main canvas and any other hidden help components*/	
config.ids.common.canvas_main	= "canvas_main";		/* main data display canvas */
config.ids.common.org_tree		= "org_tree";			/* org tree selector thingy */
config.ids.common.org_container	= "org_container";			/* org tree selector thingy */

config.css = {};
config.css.hide_me = "hide_me";
config.css.color_1 = "color_1";
config.css.color_2 = "color_2";
config.css.color_3 = "color_3";

config.page = {};
config.page[HOME]			= "/webxml/index.xml";
config.page[ADVANCED]	= "/webxml/advanced.xml";
config.page[MRESULT]		= "/webxml/mresult.xml";
config.page[RRESULT]		= "/webxml/rresult.xml";
config.page[MYOPAC]		= "/webxml/myopac/index.xml";
config.page[RDETAIL]		= "/webxml/rdetail.xml";


/* mresult */
config.ids.mresult = {};

/* result */
config.ids.result = {};
config.css.result = {};
config.names.result = {};
config.ids.result.offset_start	= "offset_start";
config.ids.result.offset_end		= "offset_end";
config.ids.result.result_count	= "result_count";
config.ids.result.next_link		= 'next_link';
config.ids.result.prev_link		= 'prev_link';
config.ids.result.home_link		= 'home_link';
config.ids.result.end_link			= 'end_link';
config.ids.result.main_table		= 'result_table';
config.ids.result.row_template	= 'result_table_template';
config.ids.result.num_pages		= 'num_pages';
config.ids.result.current_page	= 'current_page';
config.css.result.nav_active		= "nav_link_active";
config.ids.result.top_div			= "result_table_div";
config.ids.result.nav_links		= "search_nav_links";
config.ids.result.info				= "result_info_div";

config.names.result.item_jacket	= "item_jacket";
config.names.result.item_title	= "item_title";
config.names.result.item_author	= "item_author";
config.names.result.counts_row	= "counts_row";
config.names.result.count_cell	= "copy_count_cell";

/* login page */
config.ids.login = {};
config.css.login = {};
config.ids.login.box			= "login_box";
config.ids.login.username	= "login_username";
config.ids.login.password	= "login_password";
config.ids.login.button		= "login_button";
config.ids.login.cancel		= "login_cancel_button";



/* searchbar ids and css */
config.ids.searchbar = {};
config.css.searchbar = {};
config.ids.searchbar.text				= 'search_box';	
config.ids.searchbar.submit			= 'search_submit';	
config.ids.searchbar.type_selector	= 'search_type_selector';
config.ids.searchbar.depth_selector	= 'depth_selector';
config.ids.searchbar.form_selector	= 'form_selector';
config.ids.searchbar.extra_row		= 'searchbar_extra';
config.ids.searchbar.main_row			= 'searchbar_main_row';
config.ids.searchbar.table				= 'searchbar_table';
config.ids.searchbar.tag				= 'search_tag_link';
config.ids.searchbar.tag_on			= 'searchbar_tag_on';
config.ids.searchbar.tag_off			= 'searchbar_tag_off';
config.ids.searchbar.location_tag	= 'search_location_tag_link';


/*  sidebar */
config.ids.sidebar = {};
config.css.sidebar = {};
config.css.sidebar.item = {};
config.ids.sidebar.home				= 'home_link_div';
config.ids.sidebar.advanced		= 'advanced_link_div';
config.ids.sidebar.myopac			= 'myopac_link_div';
config.ids.sidebar.prefs			= 'prefs_link_div';
config.ids.sidebar.mresult			= 'mresult_link_div';
config.ids.sidebar.rresult			= 'result_link_div';
config.ids.sidebar.login			= 'login_link';
config.ids.sidebar.logout			= 'logout_link';
config.ids.sidebar.logoutbox		= 'logout_link_div';
config.ids.sidebar.loginbox		= 'login_link_div';
config.ids.sidebar.logged_in_as	= 'logged_in_as_div';
config.ids.sidebar.username_dest	= 'username_dest';



/* ---------------------------------------------------------------------------- */
/* These are pages that may replace the canvas */
/* ---------------------------------------------------------------------------- */
config.ids.altcanvas = {};
config.ids.altcanvas.login		= config.ids.login.box;
config.ids.altcanvas.org_tree	 = config.ids.common.org_container;



/* ---------------------------------------------------------------------------- */
/* Methods are defined as service:method 
	An optional 3rd component is when a method is followed by a :1, such methods
	have a staff counterpart and should have ".staff" appended to the method 
	before the method is called when in XUL mode */

var FETCH_MRCOUNT				= "open-ils.search:open-ils.search.biblio.class.count:1";
var FETCH_MRIDS				= "open-ils.search:open-ils.search.biblio.class:1";
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






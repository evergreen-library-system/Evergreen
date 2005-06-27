/* */

var globalPage						= null; /* the current top level page object */
var globalUser						= null; /* the user session */
var globalOrgTreeWidget			= null;
var globalLocation				= null;
var globalOrgTreeWidgetBox		= null;
var globalSelectedLocation		= null;
var globalSearchDepth			= null;
var globalMenuManager			= null;
var globalCopyStatus				= null;
var locationStack					= new Array();
var globalCopyLocations			= null;

var lastSearchString				= null;
var lastSearchType				= null;

/* this is true if we directed to the record detail page
	becuase of only having one hit on the record result
	page.  this allows us to back up from the detail
	page to the mr_result page */
var recordResultRedirect = false;

var loaded = false;


function addLocation(type, title) {
	try { 
		if(globalAppFrame) {
			var obj = new Object();
			obj.location = globalAppFrame.location.href;
			obj.title = title;
			locationStack[type] = obj;
		}
	} catch(E){}

}

function _test() {
	debug("At: " + (new RegExp(".+").exec(
			arguments.callee.toString()))[0].replace("{", "") );
}


function globalInit() {


	_test();
	debug(" --- XUL IS " + isXUL() );


	if( isXUL() && globalAppFrame )
		globalAppFrame.document.body.style.background = "#FFF";

	getDocument().body.onunload = cleanIEMemory;


	var page_name = globalPageTarget;

	if(!page_name) 
		throw new EXArg("globalInit requires globalPageTarget to be set");

	debug("globalInit init-ing page: " + page_name );

	switch( page_name ) {

		case "start":
			globalPage = new OPACStartPage();
			addLocation("start", "Home");
			locationStack["advanced_search"] = null;
			break;

		case  "advanced_search":
			globalPage = new AdvancedSearchPage();
			addLocation("advanced_search", "Advanced Search");
			locationStack["start"] = null;
			break;

		case  "mr_result":
			//globalPage = new MRResultPage();
			globalPage = MRResultPage.instance();
			addLocation("mr_result", "Title Group Results");
			break;

		case  "record_result":
			//globalPage = new RecordResultPage();
			globalPage = RecordResultPage.instance();
			addLocation("record_result", "Title Results");
			break;

		case  "login":
			globalPage = new LoginPage();
			break;

		case  "logout":
			globalPage = new LogoutPage();
			break;

		case  "my_opac":
			globalPage = new MyOPACPage();
			break;

		case "record_detail":
			globalPage = new RecordDetailPage();
			addLocation("record_detail", "Title Details");
			break;

		case  "about":
			globalPage = new AboutPage();
			break;

		}

	if( ! globalPage ) 
		throw new EXArg(
			"globalInit requires a valid page target: " + page_name );

	if(!loaded) { loaded = true; GlobalInitLoad(); }

	globalMenuManager = new ContextMenuManager();

	/* hide all context menus on body click */
	getDocument().body.onclick = function() {
			globalMenuManager.hideAll(); 
	}

	globalPage.init();

	if(paramObj.__location != null) {
		globalSelectedLocation = findOrgUnit(paramObj.__location);
		if(globalSelectedLocation == null) 
			debug("Invalid location in url : " + paramObj.__location);
		else
			debug("Setting selected location to " + globalSelectedLocation.name() );
	} 


	if(paramObj.__depth != null) {
		debug("Passed in depth from search params: " + paramObj.__depth);
		globalSearchDepth = parseInt(paramObj.__depth);
		debug("Setting selected depth to " + globalSearchDepth );
	}

	globalPage.setLocDisplay();
	globalPage.locationTree = globalOrgTreeWidget;
	globalPage.setPageTrail();

	if(globalSearchBarChunk)
		globalSearchBarChunk.reset();
	
	if( globalSearchBarFormChunk != null)
		globalSearchBarFormChunk.resetPage();



}


/* we only do this on loading of the outer frame (i.e. only once) */
function GlobalInitLoad() {

	debug("Global Init is doing its primary load");
	globalOrgTreeWidget = new LocationTree(globalOrgTree);
	globalUser = UserSession.instance();

	var ses = null;
	var org = null;

	if(isXUL()) {
		ses = G['auth_ses'][0]; /* G is shoved in by XUL */
		org = G['user_ou']; /* the desired location of the user */
	}

	if(globalUser.verifySession(ses)) {
		globalUser.grabOrgUnit(org);

	} else  {
		globalUser = null;
		globalLocation = globalOrgTree;
		if(globalSearchDepth == null)
			globalSearchDepth = findOrgDepth(globalOrgTree.ou_type());
	}

	grabCopyStatus();

}

function grabCopyStatus() {
	if(globalCopyStatus) return;

	debug("Grabbing copy statuses");
	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.config.copy_status.retrieve.all" );

	if(paramObj.__sub_frame) {
		/* we have to grab the copy statuses synchronously */
		req.send(true);
		globalCopyStatus = r.getResultObject();

	} else {

		req.setCompleteCallback(function(r) { 
			debug("Got globalCopyStatus");
			globalCopyStatus = r.getResultObject(); });
	
		req.send();
	}
}




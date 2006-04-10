var searchBarExpanded = false;
/* our search selector boxes */
var _ts, _fs;


var isFrontPage = false;


G.evt.common.init.push(searchBarInit);

/* if set by the org selector, this will be the location used the
	next time the search is submitted */
var newSearchLocation; 
var newSearchDepth = null;


function searchBarInit() {

	_ts = G.ui.searchbar.type_selector;
	_fs = G.ui.searchbar.form_selector;

	G.ui.searchbar.text.focus();
	G.ui.searchbar.text.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) { searchBarSubmit(); } };
	_ts.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) { searchBarSubmit(); } };
	_fs.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) { searchBarSubmit(); } };

	G.ui.searchbar.submit.onclick = searchBarSubmit;

	/* set up the selector objects, etc */
	G.ui.searchbar.text.value = (getTerm() != null) ? getTerm() : "";
	setSelector(_ts,	getStype());
	setSelector(_fs,	getForm());

	depthSelInit();


	if(!isFrontPage && (findCurrentPage() != MYOPAC)) {
		attachEvt('common','depthChanged', searchBarSubmit);
	}

}

function searchBarSubmit() {

	var text = G.ui.searchbar.text.value;

	clearSearchParams();

	if(!text || text == "") return;
	var d	= (newSearchDepth != null) ?  newSearchDepth : depthSelGetDepth();
	if(isNaN(d)) d = 0;

	var args = {};
	args.page				= MRESULT;
	//args[PARAM_OFFSET]	= 0;
	args[PARAM_TERM]		= text;
	args[PARAM_STYPE]		= _ts.options[_ts.selectedIndex].value;
	args[PARAM_LOCATION] = depthSelGetNewLoc();
	args[PARAM_DEPTH]		= d;
	args[PARAM_FORM]		= _fs.options[_fs.selectedIndex].value;

	goTo(buildOPACLink(args));
}



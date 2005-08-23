var searchBarExpanded = false;
/* our search selector boxes */
var _ts, _fs, _ds;


G.evt.common.init.push(searchBarInit);


/* if set by the org selector, this will be the location used the
	next time the search is submitted */
var newSearchLocation; 

function searchBarInit() {

	/* ----------------------------------- */
	//setActivateStyleSheet("color_test");
	/* ----------------------------------- */

	_ts = G.ui.searchbar.type_selector;
	_ds = G.ui.searchbar.depth_selector;
	_fs = G.ui.searchbar.form_selector;

	G.ui.searchbar.text.focus();
	G.ui.searchbar.text.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) searchBarSubmit();};

	G.ui.searchbar.submit.onclick = searchBarSubmit;
	G.ui.searchbar.tag.onclick = searchBarToggle;

	/* set up the selector objects, etc */
	G.ui.searchbar.text.value = (getTerm() != null) ? getTerm() : "";
	setSelector(_ts,	getStype());
	setSelector(_ds,	getDepth());
	setSelector(_fs,	getForm());
	G.ui.searchbar.location_tag.onclick = _opacHandleLocationTagClick;
}

function _opacHandleLocationTagClick() {
	orgTreeSelector.openTo(  
		(newSearchLocation != null) ? parseInt(newSearchLocation) : getLocation(), true );
	swapCanvas(G.ui.common.org_container);
}

function updateLoc(location, depth) {
	if( location != null )
		newSearchLocation = location;
	if( depth != null ) 
		setSelector(G.ui.searchbar.depth_selector, depth);
}
function searchBarSubmit() {

	var text = G.ui.searchbar.text.value;
	if(!text || text == "") return;


	var args = {};
	args.page				= MRESULT;
	args[PARAM_OFFSET]	= 0;
	args[PARAM_TERM]		= text;
	args[PARAM_STYPE]		= _ts.options[_ts.selectedIndex].value;
	args[PARAM_LOCATION] = newSearchLocation;
	args[PARAM_DEPTH]		= parseInt(_ds.options[_ds.selectedIndex].value);
	args[PARAM_FORM]		= _fs.options[_fs.selectedIndex].value;

	goTo(buildOPACLink(args));
}


function searchBarToggle() {
	if(searchBarExpanded) {
		hideMe(G.ui.searchbar.extra_row);
		hideMe(G.ui.searchbar.tag_on);
		unHideMe(G.ui.searchbar.tag_off);
	} else {
		unHideMe(G.ui.searchbar.extra_row);
		hideMe(G.ui.searchbar.tag_off);
		unHideMe(G.ui.searchbar.tag_on);
	}
	searchBarExpanded = !searchBarExpanded;
}



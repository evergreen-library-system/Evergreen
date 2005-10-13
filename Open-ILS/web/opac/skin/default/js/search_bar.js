var searchBarExpanded = false;
/* our search selector boxes */
var _ts, _fs, _ds;

attachEvt( "common", "locationChanged", updateLoc );

var isFrontPage = false;


G.evt.common.init.push(searchBarInit);

/* if set by the org selector, this will be the location used the
	next time the search is submitted */
var newSearchLocation; 
var newSearchDepth = null;

function searchBarInit() {

	_ts = G.ui.searchbar.type_selector;
	_ds = G.ui.searchbar.depth_selector;
	_fs = G.ui.searchbar.form_selector;

	G.ui.searchbar.text.focus();
	G.ui.searchbar.text.onkeypress = 
		function(evt) {if(userPressedEnter(evt)) searchBarSubmit();};

	G.ui.searchbar.submit.onclick = searchBarSubmit;

	_ds.onchange = depthSelectorChanged;

	if( getLocation() == globalOrgTree.id() ) {
		unHideMe( G.ui.searchbar.lib_sel_span );
		G.ui.searchbar.lib_sel_link.onclick = _opacHandleLocationTagClick;
	} else {
		unHideMe( G.ui.searchbar.depth_sel_span );
		buildLocationSelector();
	}

	/* set up the selector objects, etc */
	G.ui.searchbar.text.value = (getTerm() != null) ? getTerm() : "";
	setSelector(_ts,	getStype());
	setSelector(_ds,	getDepth());
	setSelector(_fs,	getForm());

}

function _opacHandleLocationTagClick() {
	orgTreeSelector.openTo(  
		(newSearchLocation != null) ? parseInt(newSearchLocation) : getLocation(), true );
	swapCanvas(G.ui.common.org_container);
}

function depthSelectorChanged() {
	var i = _ds.selectedIndex;
	if( i == _ds.options.length - 1 ) {
		setSelector( _ds, getDepth() );
		_opacHandleLocationTagClick();

	} else {
		if(!isFrontPage)
			searchBarSubmit();
	}

}

function buildLocationSelector(newLoc) {

	var loc;
	if(newLoc != null) loc = newLoc;
	else loc = getLocation();

	if( loc == globalOrgTree.id() ) return;

	var selector = G.ui.searchbar.depth_selector
	var node = selector.removeChild(selector.getElementsByTagName("option")[0]);
	removeChildren(selector);
	
	var location = findOrgUnit(loc);
	var type = findOrgType(location.ou_type());

	while( type && location ) {
		var n = node.cloneNode(true);	
		n.setAttribute("value", type.depth());
		removeChildren(n);
		n.appendChild(text(type.opac_label()));
		selector.appendChild(n);
		location = findOrgUnit(location.parent_ou());
		if(location) type = findOrgType(location.ou_type());
		else type = null;
	}

	selector.appendChild(node);
}

function updateLoc(location, depth) {
	if( location != null )
		newSearchLocation = location;

	if( depth != null ) {
		if(depth != 0 ){
			G.ui.searchbar.lib_sel_link.onclick = _opacHandleLocationTagClick;
			if( location == globalOrgTree.id() ) {
				hideMe( G.ui.searchbar.depth_sel_span );
				unHideMe( G.ui.searchbar.lib_sel_span );
			} else {
				buildLocationSelector(location);
				hideMe( G.ui.searchbar.lib_sel_span );
				unHideMe( G.ui.searchbar.depth_sel_span );
			}
		}

		setSelector(G.ui.searchbar.depth_selector, depth);
		newSearchDepth = depth;
	}

	if(!isFrontPage && (findCurrentPage() != MYOPAC))
		searchBarSubmit();

	alert(findCurrentPage());
	/*
	alert(MYOPAC);
	alert(findCurrentPage() == MYOPAC);
	*/

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
	args[PARAM_DEPTH]		= (newSearchDepth != null) ? newSearchDepth : parseInt(_ds.options[_ds.selectedIndex].value);
	args[PARAM_FORM]		= _fs.options[_fs.selectedIndex].value;

	goTo(buildOPACLink(args));
}



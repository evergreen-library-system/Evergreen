
var searchBarExpanded = false;
var searchBarTable;
var searchBarTagLink;
var searchBarExtraRow;
var searchBarMainRow;

var typeSelector;
var depthSelector;
var formSelector;
var orgTreeVisible = false;

/* if set by the org selector, this will be the location used the
	next time the search is submitted */
var newSearchLocation; 

function searchBarInit() {

	G.ui.searchbar.text.focus();
	G.ui.searchbar.text.onkeydown = 
		function(evt) {if(userPressedEnter(evt)) searchBarSubmit();};
	G.ui.searchbar.submit.onclick = searchBarSubmit;

	searchBarTable		= G.ui.searchbar.table;
	searchBarTagLink	= G.ui.searchbar.tag;
	searchBarExtraRow = G.ui.searchbar.extra_row;
	searchBarMainRow	= G.ui.searchbar.main_row;

	typeSelector = G.ui.searchbar.type_selector;
	depthSelector = G.ui.searchbar.depth_selector;
	formSelector = G.ui.searchbar.form_selector;

	searchBarTagLink.onclick = function(){searchBarToggle();}

	/* set up the selector objects, etc */
	var t = getTerm();
	if(t == null) t = "";
	G.ui.searchbar.text.value = t;
	setSelector(typeSelector,	getStype());
	setSelector(depthSelector, getDepth());
	setSelector(formSelector,	getForm());

	//typeSelector.onchange	= function(){searchBarSelectorChanged("type");};
	//depthSelector.onchange	= function(){searchBarSelectorChanged("depth");};
	//formSelector.onchange	= function(){searchBarSelectorChanged("form");};

	if(getSearchBarExtras()) searchBarToggle();

	G.ui.searchbar.location_tag.onclick = function() {
		if(orgTreeVisible) showCanvas();	
		 else swapCanvas(G.ui.common.org_tree);
		orgTreeVisible = !orgTreeVisible;
	}
}

/*
function searchBarSelectorChanged(type) {

	var args = {};
	switch( type ) {

		case "type": 
			args[PARAM_STYPE] = typeSelector.options[typeSelector.selectedIndex].value
			break;

		case "depth": 
			args[PARAM_DEPTH] = parseInt(depthSelector.options[depthSelector.selectedIndex].value);
			break;

		case "form": 
			args[PARAM_FORM] = formSelector.options[formSelector.selectedIndex].value;
			break;
	}

	args[PARAM_OFFSET] = 0;

	if(findCurrentPage() == MRESULT || findCurrentPage() == RRESULT )
		goTo(buildOPACLink(args));
}
*/

function searchBarSubmit() {
	var text = G.ui.searchbar.text.value;
	if(!text || text == "") return;
	var type_s = G.ui.searchbar.type_selector;

	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = text;
	args[PARAM_STYPE] = type_s.options[type_s.selectedIndex].value;
	args[PARAM_LOCATION] = newSearchLocation;

	args[PARAM_DEPTH] = parseInt(depthSelector.options[depthSelector.selectedIndex].value);
	args[PARAM_FORM] = formSelector.options[formSelector.selectedIndex].value;
	goTo(buildOPACLink(args));
}


function searchBarToggle() {

	if(searchBarExpanded) {

		hideMe(searchBarExtraRow);
		searchBarExpanded = false;
		hideMe(G.ui.searchbar.tag_on);
		unHideMe(G.ui.searchbar.tag_off);
		//SEARCHBAR_EXTRAS = 0; set cookie...

	} else {

		removeCSSClass(searchBarExtraRow,config.css.hide_me);
		searchBarExpanded = true;
		hideMe(G.ui.searchbar.tag_off);
		unHideMe(G.ui.searchbar.tag_on);
		//SEARCHBAR_EXTRAS = 1; set cookie...
	}
}



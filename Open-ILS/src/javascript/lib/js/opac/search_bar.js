
var searchBarExpanded = false;
var searchBarTable;
var searchBarTagLink;
var searchBarExtraRow;
var searchBarMainRow;

var typeSelector;
var depthSelector;
var formSelector;

function searchBarInit() {

	getId(config.ids.searchbar.text).focus();
	getId(config.ids.searchbar.text).onkeydown = 
		function(evt) {if(userPressedEnter(evt)) searchBarSubmit();};
	getId(config.ids.searchbar.submit).onclick = searchBarSubmit;

	searchBarTable		= getId(config.ids.searchbar.table);
	searchBarTagLink	= getId(config.ids.searchbar.tag);
	searchBarExtraRow = getId(config.ids.searchbar.extra_row);
	searchBarMainRow	= getId(config.ids.searchbar.main_row);

	typeSelector = getId(config.ids.searchbar.type_selector);
	depthSelector = getId(config.ids.searchbar.depth_selector);
	formSelector = getId(config.ids.searchbar.form_selector);

	searchBarTagLink.onclick = function(){searchBarToggle();}

	/* set up the selector objects, etc */
	var t = getTerm();
	if(t == null) t = "";
	getId(config.ids.searchbar.text).value = t;
	setSelector(typeSelector,	getStype());
	setSelector(depthSelector, getDepth());
	setSelector(formSelector,	getForm());

	//typeSelector.onchange	= function(){searchBarSelectorChanged("type");};
	//depthSelector.onchange	= function(){searchBarSelectorChanged("depth");};
	//formSelector.onchange	= function(){searchBarSelectorChanged("form");};

	if(getSearchBarExtras()) searchBarToggle();
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
	var text = getId(config.ids.searchbar.text).value;
	if(!text || text == "") return;
	var type_s = getId(config.ids.searchbar.type_selector);

	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = text;
	args[PARAM_STYPE] = type_s.options[type_s.selectedIndex].value;

	args[PARAM_DEPTH] = parseInt(depthSelector.options[depthSelector.selectedIndex].value);
	args[PARAM_FORM] = formSelector.options[formSelector.selectedIndex].value;
	goTo(buildOPACLink(args));
}


function searchBarToggle() {

	if(searchBarExpanded) {

		addCSSClass(searchBarExtraRow,config.css.hide_me);
		searchBarExpanded = false;
		getId(config.ids.searchbar.tag_off).className = "show_me_inline";
		getId(config.ids.searchbar.tag_on).className = "hide_me";
		//SEARCHBAR_EXTRAS = 0; set cookie...

	} else {

		removeCSSClass(searchBarExtraRow,config.css.hide_me);
		searchBarExpanded = true;
		getId(config.ids.searchbar.tag_off).className = "hide_me";
		getId(config.ids.searchbar.tag_on).className = "show_me_inline";
		//SEARCHBAR_EXTRAS = 1; set cookie...
	}
}



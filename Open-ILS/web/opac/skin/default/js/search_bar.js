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

	try{G.ui.searchbar.text.focus();}catch(e){}
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

    if( (limit = $('opac.result.limit2avail')) ) {
        if(getAvail()) limit.checked = true;
        if(getSort() && getSortDir()) 
            setSelector($('opac.result.sort'), getSort()+'.'+getSortDir());
    }
}

function searchBarSubmit(isFilterSort) {

	var text = G.ui.searchbar.text.value;

	clearSearchParams();

	if(!text || text == "") return;

	/* old JSON format breaks horribly if fed backslashes */
    text = text.replace(/\\/g,' ');

	var d	= (newSearchDepth != null) ?  newSearchDepth : depthSelGetDepth();
	if(isNaN(d)) d = 0;

	var args = {};

	if(SHOW_MR_DEFAULT || (isFilterSort && findCurrentPage() == MRESULT)) {
		args.page				= MRESULT;
	} else {
		args.page				= RRESULT;
		args[PARAM_RTYPE]		= _ts.options[_ts.selectedIndex].value;
	}

	args[PARAM_STYPE]		= _ts.options[_ts.selectedIndex].value;
	args[PARAM_TERM]		= text;
	args[PARAM_LOCATION] = depthSelGetNewLoc();
	args[PARAM_DEPTH]		= d;
	args[PARAM_FORM]		= _fs.options[_fs.selectedIndex].value;

    if($('opac.result.limit2avail')) {
        args[PARAM_AVAIL] = ($('opac.result.limit2avail').checked) ? 1 : '';
        if( (val = getSelectorVal($('opac.result.sort'))) ) {
            args[PARAM_SORT] = val.split('.')[0]
            args[PARAM_SORT_DIR] = val.split('.')[1]
        }
    }

	goTo(buildOPACLink(args));
}



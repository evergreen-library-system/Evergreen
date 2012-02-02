var searchBarExpanded = false;
/* our search selector boxes */
var _ts, _fs;


var isFrontPage = false;


G.evt.common.init.push(searchBarInit);

/* if set by the org selector, this will be the location used the
	next time the search is submitted */
var newSearchLocation; 
var newSearchDepth = null;

function autoSuggestInit() {
    var org_unit_getter = null;
    var global_flag = fieldmapper.standardRequest(
        ["open-ils.fielder", "open-ils.fielder.cgf.atomic"], [{
            "query": {"name": "opac.use_autosuggest"},
            "fields": ["enabled", "value"]
        }]
    ).shift();  /* XXX do we want to use caching here? a cookie? */

    if (!global_flag || !isTrue(global_flag.enabled))
        return;
    else if (global_flag.value && global_flag.value.match(/opac_visible/))
        org_unit_getter = depthSelGetNewLoc;

    dojo.require("openils.widget.AutoSuggest");

    /* See comments in openils.AutoSuggestStore, esp. near the constructor,
     * to find out what you can control with the store_args object. */
    var widg = new openils.widget.AutoSuggest(
        {
            "store_args": {
                "org_unit_getter": org_unit_getter
            },
            "type_selector": G.ui.searchbar.type_selector,
            "submitter": searchBarSubmit,
            "style": {"width": dojo.style("search_box", "width")},
            "value": ((getTerm() != null) ? getTerm() : "")
        }, "search_box"
    );

    G.ui.searchbar.text = widg.textbox;
    setTimeout(function() { widg.focus(); }, 1000);/* raise chance of success */
}

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
	if (!isFrontPage) G.ui.searchbar.facets.value = (getFacet() != null) ? getFacet() : "";
	setSelector(_ts,	getStype());
	setSelector(_fs,	getItemType());

	depthSelInit();


	if(!isFrontPage && (findCurrentPage() != MYOPAC)) {
		attachEvt('common','depthChanged', searchBarSubmit);
	}

    if( (limit = $('opac.result.limit2avail')) ) {
        if(getAvail()) limit.checked = true;
        if(getSort() && getSortDir()) 
            setSelector($('opac.result.sort'), getSort()+'.'+getSortDir());
    }

    autoSuggestInit();
}

function searchBarSubmit(isFilterSort) {

	var text = G.ui.searchbar.text.value;
	var facet_text = isFrontPage ? '' : G.ui.searchbar.facets.value;

    if (!isFilterSort) {	
        clearSearchParams();
    }

	if(!text || text == "") return;

	var d	= (newSearchDepth != null) ?  newSearchDepth : depthSelGetDepth();
	if(isNaN(d)) d = 0;

	var args = {};

	if(SHOW_MR_DEFAULT || findCurrentPage() == MRESULT) {
		args.page				= MRESULT;
	} else {
		args.page				= RRESULT;
		args[PARAM_RTYPE]		= _ts.options[_ts.selectedIndex].value;
	}

	args[PARAM_STYPE]		= _ts.options[_ts.selectedIndex].value;
	args[PARAM_TERM]		= text;
	args[PARAM_FACET]		= facet_text;
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



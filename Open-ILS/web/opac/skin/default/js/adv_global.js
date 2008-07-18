
attachEvt("common", "run", advgInit);
attachEvt("common", "locationChanged", advSyncCopyLocLink );

var COOKIE_NOGROUP_RECORDS = 'grpt';
var advSelectedOrg = null;

function advgInit() {

	/* XXX */
	if( cookieManager.read(COOKIE_NOGROUP_RECORDS) || SHOW_MR_DEFAULT )
		$('adv_group_titles').checked = true;

	$n($('adv_global_tbody'), 'term').focus();

	var extras = [ 
		FETCH_LIT_FORMS, 
		FETCH_ITEM_FORMS, 
		FETCH_ITEM_TYPES, 
		FETCH_AUDIENCES ];

	for( var x in extras ) {

		var req = new Request(extras[x]);

		if(x == 0) req.request.sel = $('adv_global_lit_form');
		if(x == 1) req.request.sel = $('adv_global_item_form');
		if(x == 2) req.request.sel = $('adv_global_item_type');
		if(x == 3) req.request.sel = $('adv_global_audience');

		req.callback(advDrawBibExtras);
		req.send();
	}

	var input = $n($('adv_global_trow'), 'term');
	input.focus();
	setEnterFunc(input, advSubmitGlobal);

    if(getSort() && getSortDir()) {
	    setSelector($('adv_global_sort_by'), getSort());
	    setSelector($('adv_global_sort_dir'), getSortDir());
        if(getSort() != 'rel')
            $('adv_global_sort_dir').disabled = false;
    }

    if(getAvail())
        $('opac.result.limit2avail').checked = true;

    initSearchBoxes();

    advSyncCopyLocLink(getLocation());
}

function advSyncCopyLocLink(org) {
    // display the option to filter by copy location
    advLocationsLoaded = false;
    advSelectedOrg = org;
    removeChildren($('adv_copy_location_filter_select'));

    if(isTrue(findOrgType(findOrgUnit(org).ou_type()).can_have_vols())) {
        unHideMe($('adv_copy_location_filter_row'));
        advLoadCopyLocations(org); 
    } else {
        hideMe($('adv_copy_location_filter_row'));
    }

}


function clearSearchBoxes() {
    var rows = $('adv_global_tbody').getElementsByTagName('tr');
    for(var t = 0; t < rows.length; t++) {
        if($n(rows[t], 'term')) {
            $n(rows[t], 'term').value = '';
            setSelector($n(rows[t], 'container'), 'contains');
            setSelector($n(rows[t], 'type'), 'keyword');
        }
    }
    $n(rows[0], 'term').focus();
}


function initSearchBoxes() {
    /* loads the compiled search from the search cookie 
        and sets the widgets accordingly */

    search = cookieManager.read(COOKIE_SEARCH);
    if(!search) return;
    _debug("loaded compiled search cookie: " + search);

    search = JSON2js(search);
    if(!search) return;

    var types = getObjectKeys(search.searches);

    /* pre-add the needed rows */
    while($('adv_global_tbody').getElementsByTagName('tr').length - 1 < types.length)
        advAddGblRow();

    var rows = $('adv_global_tbody').getElementsByTagName('tr');
    for(var t = 0; t < types.length; t++) {
        var row = rows[t];
        setSelector($n(row, 'type'), types[t]);
        var term = search.searches[types[t]].term;

        /* if this is a single -<term> search, set the selector to nocontains */
        if(match = term.match(/^-(\w+)$/)) {
            term = match[1];
            setSelector($n(row, 'contains'), 'nocontains');
        }
        $n(row, 'term').value = term;
    }
}

function advAddGblRow() {
	var tbody = $("adv_global_tbody");
	var newrow = $("adv_global_trow").cloneNode(true);
	tbody.insertBefore(newrow, $("adv_global_addrow"));
	var input = $n(newrow, "term");
	input.value = "";
	setEnterFunc(input, advSubmitGlobal);
	$n(newrow, 'type').focus();
}

function advDrawBibExtras(r) {
	var data = r.getResultObject();
	var sel = r.sel;

	data = data.sort( /* sort alphabetically */
		function(a,b) { 
			if( a.value() < b.value() ) return -1;
			if( a.value() > b.value() ) return 1;
			return 0;
		}
	);

	for( var d = 0; d < data.length; d++ ) {
		var thing = data[d];
		var opt = insertSelectorVal( sel, -1, thing.value(), thing.code() );
		opt.setAttribute('title', thing.value());
	}
}

function advSelToStringList(sel) {
	var list = getSelectedList(sel);
	var vals = [];
	for( var i = 0; i < list.length; i++ ) {
		var str = list[i];
		for( var j = 0; j < str.length; j++ ) {
			//if(str.charAt(j) == ' ') continue;
			vals.push(str.charAt(j));
		}
	}
	return vals.toString();
}

function advGetVisSelectorVals(id) {
	var basic = id + '_basic';
	if(! $(id).className.match(/hide_me/)) 
		return advSelToStringList($(id));
	return advSelToStringList($(basic));
}

function advSubmitGlobal() {
	
	var sortdir = getSelectorVal($('adv_global_sort_dir'));
	var sortby  = getSelectorVal($('adv_global_sort_by'));

	var litforms  = advGetVisSelectorVals('adv_global_lit_form');
	var itemforms = advGetVisSelectorVals('adv_global_item_form');
	var itemtypes = advGetVisSelectorVals('adv_global_item_type');
	var audiences = advGetVisSelectorVals('adv_global_audience');
    var locations = advGetVisSelectorVals('adv_copy_location_filter_select');
	var languages = getSelectedList($('adv_global_lang')) + '';	
    var limit2avail = $('opac.result.limit2avail').checked ? 1 : ''

	var searches = advBuildSearchBlob();
	if(!searches) return;

	clearSearchParams();

	var args = {};
	args.page = MRESULT;
	args[PARAM_ITEMFORM] = itemforms;
	args[PARAM_ITEMTYPE] = itemtypes;
	args[PARAM_LITFORM]	= litforms;
	args[PARAM_AUDIENCE]	= audiences;
	args[PARAM_LANGUAGE] = languages;
	args[PARAM_COPYLOCS] = locations;
	//args[PARAM_SEARCHES]	= js2JSON(searches); /* break these out */
	args[PARAM_DEPTH]		= depthSelGetDepth();
	args[PARAM_LOCATION]	= depthSelGetNewLoc();
	args[PARAM_SORT]		= sortby;
	args[PARAM_SORT_DIR]	= sortdir;
	args[PARAM_ADVTYPE]	= ADVTYPE_MULTI;
	args[PARAM_STYPE]		= "";
	args[PARAM_TERM]		= searches;
	args[PARAM_AVAIL]		= limit2avail;

	/* pubdate sorting causes a record (not metarecord) search */
	if( sortby == SORT_TYPE_PUBDATE || !$('adv_group_titles').checked ) {
		args.page = RRESULT;
		args[PARAM_RTYPE] = RTYPE_MULTI;
	}

	if($('adv_group_titles').checked ) 
		cookieManager.write(COOKIE_NOGROUP_RECORDS,'1',-1);
	else
		cookieManager.write(COOKIE_NOGROUP_RECORDS,'');


	goTo(buildOPACLink(args));
}


function advBuildSearchBlob() {

	var searches = '';
	var tbody    = $('adv_global_tbody');
	var rows     = tbody.getElementsByTagName('tr');

	for( var i = 0; i < rows.length; i++ ) {

		var row = rows[i];
		if(!(row && typeof row == 'object')) continue;
		if(!row.getAttribute('type')) continue;
		
		var stype	 = getSelectorVal($n(row, 'type'));
		var contains = getSelectorVal($n(row, 'contains'));
		var term		 = $n(row, 'term').value;
		if(!term) continue;

		var string = "";
		switch(contains) {
			case 'contains' : 
				string += " " + term; 
				break;

			case 'nocontains' : {
				var words = term.split(" ");
					for( var j in words ) 
						string += " -" + words[j];
				}
				break;

			case 'exact' : 
				if(term.indexOf('"') > -1) string += " " + term;
				else string += " \"" + term + "\"";
				break;
		}
		if(string) {
			string = string.replace(/'/g,' ');
			string = string.replace(/\\/g,' ');
            string = string.replace(/^\s*/,'');
            string = string.replace(/\s*$/,'');
			//searches[stype].term = string;
            if(searches) searches += ' ';
            searches += stype + ':'+ string;
		}
	}

    _debug("created search query " + searches);
	return searches;
}


// retrieves the shelving locations
var advLocationsLoaded = false;
function advLoadCopyLocations(org) {
    if(org == null) 
        org = advSelectedOrg;
    var req = new Request(FETCH_COPY_LOCATIONS, org);
    req.callback(advShowCopyLocations);
    req.send();
    advLocationsLoaded = true;
}

// inserts the shelving locations into the multi-select
function advShowCopyLocations(r) {
    var locations = r.getResultObject();
    var sel = $('adv_copy_location_filter_select');
    for(var i = 0; i < locations.length; i++) 
        insertSelectorVal(sel, -1, locations[i].name(), locations[i].id());
}



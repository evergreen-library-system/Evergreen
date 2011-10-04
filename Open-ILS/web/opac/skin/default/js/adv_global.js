
attachEvt("common", "run", advgInit);
attachEvt("common", "locationChanged", advSyncCopyLocLink );

var COOKIE_NOGROUP_RECORDS = 'grpt';
var advSelectedOrg = null;

function advgInit() {

	/* XXX */
    dojo.require('dojo.cookie');
	if( dojo.cookie(COOKIE_NOGROUP_RECORDS) || SHOW_MR_DEFAULT )
		$('adv_group_titles').checked = true;

	$n($('adv_global_tbody'), 'term').focus();

    var ctypes = ["bib_level", "item_form", "item_type", "audience", "lit_form"];

    var req = new Request('open-ils.fielder:open-ils.fielder.ccvm.atomic', {"cache":1,"query":{"ctype":ctypes}});
    req.callback(advDrawBibExtras);
    req.request.ctypes = ctypes;
    req.send();

	var input = $n($('adv_global_trow'), 'term');
	input.focus();

    var rows = $('adv_global_tbody').getElementsByTagName('tr');
    for(var t = 0; t < rows.length; t++) {
        if($n(rows[t], 'term')) {
            setEnterFunc($n(rows[t], 'term'), advSubmitGlobal);
        }
    }

    if(getSort() && getSortDir()) {
	    setSelector($('adv_global_sort_by'), getSort());
	    setSelector($('adv_global_sort_dir'), getSortDir());
        if(getSort() != 'rel')
            $('adv_global_sort_dir').disabled = false;
    }

    if(getAvail())
        $('opac.result.limit2avail').checked = true;

    // not sure we want to propogate the pubdate filter, 
    // since other filters are not propogated
    //advInitPubFilter();

    if(!new CGI().param(PARAM_NOPERSIST_SEARCH))
        initSearchBoxes();
    advSyncCopyLocLink(getLocation());
}

function advInitPubFilter() {
    var i1 = $('adv_global_pub_date_1');
    var i2 = $('adv_global_pub_date_2');
    var sel = $('adv_global_pub_date_type');
    if(getPubdBefore()) {
        i1.value = getPubdBefore();
        setSelector(sel, 'before');
    } else if(getPubdAfter()) {
        i1.value = getPubdAfter();
        setSelector(sel, 'after');
    } else if(getPubdBetween()) {
        var values = getPubdBetween().split(','); 
        i1.value = values[0]
        if(values[0] == values[1]) {
            setSelector(sel, 'equals');
        } else {
            setSelector(sel, 'between');
            i2.value = values[1];
        }
    }
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
            setSelector($n(rows[t], 'contains'), 'contains');
            setSelector($n(rows[t], 'type'), 'keyword');
        }
    }
    $n(rows[0], 'term').focus();
}


function initSearchBoxes() {
    /* loads the compiled search from the search cookie 
        and sets the widgets accordingly */

    search = dojo.cookie(COOKIE_SEARCH);
    if(!search) return;
    _debug("loaded compiled search cookie: " + search);

    search = JSON2js(search);
    if(!search) return;

    var types = getObjectKeys(search.searches);

    // if we have browser cached data, clear it before populating from cookie
    if (search.searches[types[0]].term)
        clearSearchBoxes();

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
    var ctypes = r.ctypes
    dojo.forEach(ctypes,
        function(ctype) {
	        var sel = $('adv_global_' + ctype);
            var ctypeData = dojo.filter(data, function(item) { return item.ctype == ctype } );
            ctypeData = ctypeData.sort(
                function(a,b) { /* sort alphabetically */
                    return (a.value < b.value) ? -1 : 1;
                }
            );
            dojo.forEach(ctypeData,
                function(thing) {
                    var opt = insertSelectorVal(sel, -1, thing.value, thing.code);
                    opt.setAttribute('title', thing.value);
                }
            );
        }
    );
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
	var biblevels = advGetVisSelectorVals('adv_global_bib_level');
    var locations = getSelectedList($('adv_copy_location_filter_select')) + '';
	var languages = getSelectedList($('adv_global_lang')) + '';	
    var limit2avail = $('opac.result.limit2avail').checked ? 1 : ''

	var searches = advBuildSearchBlob();
	if(!searches) return;

	clearSearchParams();

	var args = {};
	args.page = MRESULT;
	args[PARAM_ITEMFORM] = itemforms;
	args[PARAM_ITEMTYPE] = itemtypes;
	args[PARAM_BIBLEVEL] = biblevels;
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

    // publicate year filtering
    var pub1;
    if( (pub1 = $('adv_global_pub_date_1').value) && (''+pub1).match(/\d{4}/)) {
        switch(getSelectorVal($('adv_global_pub_date_type'))) {
            case 'equals':
	            args[PARAM_PUBD_BETWEEN] = pub1+','+pub1;
                break;
            case 'before':
	            args[PARAM_PUBD_BEFORE] = pub1;
                break;
            case 'after':
	            args[PARAM_PUBD_AFTER] = pub1;
                break;
            case 'between':
                var pub2 = $('adv_global_pub_date_2').value;
                if((''+pub2).match(/\d{4}/))
	                args[PARAM_PUBD_BETWEEN] = pub1+','+pub2;
                break;
        }
    }

	/* pubdate sorting causes a record (not metarecord) search */
	if( sortby == SORT_TYPE_PUBDATE || !$('adv_group_titles').checked ) {
		args.page = RRESULT;
		args[PARAM_RTYPE] = RTYPE_MULTI;
	}

	if($('adv_group_titles').checked ) 
		dojo.cookie(COOKIE_NOGROUP_RECORDS,'1');
	else
		dojo.cookie(COOKIE_NOGROUP_RECORDS,null,{'expires':-1});


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
	    			// Normalize spaces so we don't get "- " embedded in the query
	    			var words = term.replace(/\s+/g,' ').replace(/^\s*/,'').replace(/\s*$/,'').split(" ");
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
			string = string.replace(/\\/g,' ');
            string = string.replace(/^\s*/,'');
            string = string.replace(/\s*$/,'');
			//searches[stype].term = string;
            if(searches) searches += ' ';
            searches += stype + ': '+ string;
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



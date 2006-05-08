//var records = {};
var records = [];
var ranks = [];
var onlyrecord = {};
var table;
var mresultPreCache = 200;
var searchTimer;

attachEvt("common", "unload", mresultUnload);
attachEvt("common", "run", mresultDoSearch);
attachEvt("result", "idsReceived", mresultSetRecords); 
attachEvt("result", "idsReceived", mresultCollectRecords); 

function mresultUnload() { removeChildren(table); table = null;}

hideMe($('copyright_block')); 

function mresultDoSearch() {


	TFORM = null; /* clear the rresult tform var so it's not propogated */

	if(getOffset() == 0) {
		swapCanvas($('loading_alt'));
		/*
		searchTimer = new Timer('searchTimer',$('loading_alt_span'));
		searchTimer.start();
		*/
	}

	table = G.ui.result.main_table;

	while( table.parentNode.rows.length <= (getDisplayCount() + 1) )  
		table.appendChild(G.ui.result.row_template.cloneNode(true));

	if( (getSearches() || getAdvTerm()) && !getTerm() ) {
		if(getAdvType() == ADVTYPE_MULTI ) mresultCollectAdvIds();
		if(getAdvType() == ADVTYPE_MARC ) mresultCollectAdvMARCIds();
		if(getAdvType() == ADVTYPE_ISBN ) mresultCollectAdvISBNIds();
		if(getAdvType() == ADVTYPE_ISSN ) mresultCollectAdvISSNIds();

	} else {
		_mresultCollectIds(); 
		ADVTERM = "";
		ADVTYPE = "";
	}
}

function mresultLoadCachedSearch() {
	if( (getOffset() > 0) && (getOffset() < mresultPreCache) ) {
		var c = JSON2js(cookieManager.read(COOKIE_IDS));
		if(c) { records = c[0]; ranks = c[1]; }
	}
}

function mresultTryCachedSearch() {
	mresultLoadCachedSearch();
	if(	getOffset() != 0 && records[getOffset()] != null && 
			records[resultFinalPageIndex()] != null) {
		runEvt('result', 'hitCountReceived');
		mresultCollectRecords(); 
		return true;
	}
	return false;
}

/*
function _mresultParseQuery() {
	var term = getTerm();
	var matches = term.match(/(\w+=\w+)/g);
	var type = true;
	if( matches ) {
		var args = {};
		for( var i = 0; i < matches.length; i++ ) {
			var search = matches[i];
			var stype = search.replace(/=\w+/,"");
			var term = search.replace(/\w+=/,"");
			args[stype] = { 'term' : term };
		}
		 ADVTERM = js2JSON(args);
		type = false;
	}
	return type;
}
*/

/*
function _mresultCollectIds() { _mresultCollectSearchIds(true); }
function mresultCollectAdvIds() { _mresultCollectSearchIds(false); }
*/

function _mresultCollectIds() { 
	if(getOffset() != 0 && mresultTryCachedSearch()) return; 
	resultCollectSearchIds(true, SEARCH_MRS, mresultHandleMRIds ); 
}

function mresultCollectAdvIds() { 
	if(getOffset() != 0 && mresultTryCachedSearch()) return; 
	resultCollectSearchIds(false, SEARCH_MRS, mresultHandleMRIds ); 
}

/*
function _mresultCollectSearchIds( type ) {

	if(getOffset() != 0 && mresultTryCachedSearch()) return; 

	var sort		= (getSort() == SORT_TYPE_REL) ? null : getSort(); 
	var sortdir = (sort) ? ((getSortDir()) ? getSortDir() : SORT_DIR_ASC) : null;

	var item_type;
	var item_form;
	var args = {};

	if( type ) {
		args.searches = {};
		args.searches[getStype()] = {};
		args.searches[getStype()].term = getTerm();

		var form = parseForm(getForm());
		item_type = form.item_type;
		item_form = form.item_form;

	} else {
		args.searches = JSON2js(getSearches());
		item_type = (getItemType()) ? getItemType().split(/,/) : null;
		item_form = (getItemForm()) ? getItemForm().split(/,/) : null;
	}

	args.org_unit = getLocation();
	args.depth    = getDepth();
	args.limit    = mresultPreCache;
	args.offset   = getOffset();

	if(sort) args.sort = sort;
	if(sortdir) args.sort_dir = sortdir;
	if(item_type) args.item_type	= item_type;
	if(item_form) args.item_form	= item_form;

	if(getAudience()) args.audience = getAudience().split(/,/);
	if(getLitForm()) args.lit_form	= getLitForm().split(/,/);

	alert(js2JSON(args));

	var req = new Request(SEARCH_MRS, args);
	req.callback(mresultHandleMRIds);
	req.send();
}
*/


function mresultCollectAdvMARCIds() {
	if(!mresultTryCachedSearch()) {
		var form = (getForm() == "all") ? null : getForm();
		alert(form + ' : ' + getLocation() + " : " + getAdvTerm());
		var req = new Request(FETCH_ADV_MARC_MRIDS, 
			JSON2js(getAdvTerm()), getLocation(), form );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}

function mresultCollectAdvISBNIds() {
	if(!mresultTryCachedSearch()) {
		var req = new Request(FETCH_ADV_ISBN_MRIDS, getAdvTerm() );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}

function mresultCollectAdvISSNIds() {
	if(!mresultTryCachedSearch()) {
		var req = new Request(FETCH_ADV_ISSN_MRIDS, getAdvTerm() );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}


function mresultHandleMRIds(r) {
	var res = r.getResultObject();
	if(res.count != null) {
		if( getOffset() == 0 ) HITCOUNT = res.count;
		runEvt('result', 'hitCountReceived');
	} 
	runEvt('result', 'idsReceived', res.ids);
}

function mresultSetRecords(idstruct) {
	if(!idstruct) return;
	var o = getOffset();

	for( var x = o; x < idstruct.length + o; x++ ) {
		if( idstruct[x-o] != null ) {
			var r = parseInt(idstruct[x - o][0]);
			var ra = parseFloat(idstruct[x - o][1]);
			var or = parseInt(idstruct[x - o][2]);
			if(!isNull(r) && !isNaN(r)) records[x] = r;
			if(!isNull(ra) && !isNaN(ra)) ranks[x] = ra;
			if(!isNull(or) && !isNaN(or)) onlyrecord[x] = or;
		}
	}

	if(getOffset() == 0) {
		cookieManager.remove(COOKIE_IDS);
		cookieManager.write(COOKIE_IDS, js2JSON([ records, ranks ]), '+1d' );
	}

	TOPRANK = ranks[getOffset()];
}

function mresultCollectRecords() {
	if(getHitCount() > 0 ) runEvt("result", "preCollectRecords");
	var i = 0;
	for( var x = getOffset(); x!= getDisplayCount() + getOffset(); x++ ) {
		if(isNull(records[x])) break;
		if(isNaN(records[x])) continue;
		var req = new Request(FETCH_MRMODS, records[x]);
		req.request.userdata = i++;
		req.callback(mresultHandleMods);
		req.send();
	}
}

function mresultHandleMods(r) {
	var rec = r.getResultObject();
	var pagePosition = r.userdata;
	runEvt('result', 'recordReceived', rec, pagePosition, true);
	resultCollectCopyCounts(rec, pagePosition, FETCH_MR_COPY_COUNTS);
	if(resultPageIsDone()) {
		runEvt('result', 'allRecordsReceived', recordsCache);
		unHideMe($('copyright_block')); /* *** */
	}
}





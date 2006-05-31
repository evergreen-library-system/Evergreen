var records = new Array();
var table;
var rowtemplate;
var rresultLimit = 200;

function rresultUnload() { removeChildren(table); table = null;}

attachEvt("common", "unload", rresultUnload);
attachEvt("common", "run", rresultDoSearch);
attachEvt("result", "idsReceived", rresultCollectRecords); 
attachEvt("result", "recordDrawn", rresultLaunchDrawn); 

hideMe($('copyright_block')); 

function rresultDoSearch() {

	swapCanvas($('loading_alt'));
	/*
	if(getOffset() == 0) swapCanvas($('loading_alt'));
	*/

	table = G.ui.result.main_table;
	hideMe(G.ui.result.row_template);
	while( table.parentNode.rows.length <= (getDisplayCount() +1) ) 
		hideMe(table.appendChild(G.ui.result.row_template.cloneNode(true)));
	rresultCollectIds();
}

function rresultCollectIds() {
	var ids;
	switch(getRtype()) {

		case RTYPE_COOKIE:
			ids = JSON2js(cookieManager.read(COOKIE_RIDS));
			_rresultHandleIds( ids, ids.length );
			break;

		case RTYPE_TITLE:
		case RTYPE_AUTHOR:
		case RTYPE_SUBJECT:
		case RTYPE_SERIES:
		case RTYPE_KEYWORD:
			rresultDoRecordSearch();
			break;

		case RTYPE_MULTI:
			rresultDoRecordMultiSearch();
			break;
			
		case RTYPE_LIST :
			rresultHandleList();
			break;

		case RTYPE_MARC :
			rresultCollectMARCIds();
			break;

		case RTYPE_ISBN :
			rresultCollectISBNIds();
			break;

		case RTYPE_ISSN :
			rresultCollectISSNIds();
			break;


		case RTYPE_MRID :
		case null :
		case "" :
		defaut:
			var form = rresultGetForm();
			var args = { format : form, org : getLocation(), depth : rresultGetDepth() };
			var req = new Request(FETCH_RIDS, getMrid(), args);
			req.callback( rresultHandleRIds );
			req.send();

			if( rresultGetDepth() != findOrgDepth(globalOrgTree) ) {
				unHideMe($('rresult_show_all'));
				var link = $('rresult_show_all_link');
				link.appendChild( text(
					findOrgType(globalOrgTree.ou_type()).opac_label()));

			} else {
				if( rresultGetDepth() != getDepth() ) { /* inside a limited display */
					var link = $('rresult_show_here_link');
					link.appendChild( text(
						findOrgType(findOrgUnit(getLocation()).ou_type()).opac_label()));
					unHideMe($('rresult_show_here'));
				}
			}
	}
}

function rresultExpandSearch() {
	var args = {};
	args[PARAM_RDEPTH] = findOrgDepth(globalOrgTree);
	goTo(buildOPACLink(args));
}

function rresultContractSearch() {
	var args = {};
	RDEPTH = null;
	args[PARAM_OFFSET] = 0;
	goTo(buildOPACLink(args));
}


function rresultGetDepth() {
	if( getRdepth() != null) return getRdepth();
	return getDepth();
}


function rresultGetForm() {
	var form;

	if(getTform())  /* did the user select a format from the icon list (temporary) */
		form = (getTform() == 'all') ? null : getTform();
	else  /* did the use select a format from simple search dropdown */
		form = (getForm() == 'all') ? null : getForm();

	if(!form) { /* did the user select a format from the advanced search */
		form = getItemType();
		var f = getItemForm();

		if(form) {
			form = form.replace(/,/,'');
			if(f) form += '-' + f;
		} else {
			if(f) form = '-' + f;
		}
	}

	return form;
}


function rresultCollectMARCIds() {

	var args			= {};
	args.searches	= JSON2js(getSearches());
	args.limit		= 200;
	args.org_unit	= globalOrgTree.id();
	args.depth		= 0;

	var req = new Request(FETCH_ADV_MARC_MRIDS, args);
	req.callback(rresultHandleRIds);
	req.request.noretry = true;
	req.send();
}


function rresultCollectISBNIds() {
	var req = new Request(FETCH_ADV_ISBN_RIDS, getAdvTerm() );
	req.callback(
		function(r) {
			var blob = r.getResultObject();
			_rresultHandleIds(blob.ids, blob.count);
		}
	);
	req.send();
}

function rresultCollectISSNIds() {
	var req = new Request(FETCH_ADV_ISSN_RIDS, getAdvTerm() );
	req.callback(
		function(r) {
			var blob = r.getResultObject();
			_rresultHandleIds(blob.ids, blob.count);
		}
	);
	req.send();
}

function rresultHandleList() {
	var ids = new CGI().param(PARAM_RLIST);
	if(ids) _rresultHandleIds(ids, ids.length);
}

var rresultTries = 0;
function rresultHandleRIds(r) {
	var res = r.getResultObject();

	if( res.count == 0 && rresultTries == 0 && ! r.noretry) {

		rresultTries++;
		var form = rresultGetForm();
		var args = { format : form, org : getLocation(), depth : findOrgDepth(globalOrgTree) };
		var req = new Request(FETCH_RIDS, getMrid(), args );
		req.callback( rresultHandleRIds );
		req.send();
		unHideMe($('no_formats'));
		hideMe($('rresult_show_all'));

	} else {

		_rresultHandleIds(res.ids, res.count);
	}
}

function _rresultHandleIds(ids, count) {
	HITCOUNT = parseInt(count);
	runEvt('result', 'hitCountReceived');
	runEvt('result', 'idsReceived', ids);
}

function rresultCollectRecords(ids) {
	runEvt("result", "preCollectRecords");
	var x = 0;
	for( var i = getOffset(); i!= getDisplayCount() + getOffset(); i++ ) {
		if(ids[i] == null) break;
		var req = new Request(FETCH_RMODS, parseInt(ids[i]));
		req.callback(rresultHandleMods);
		req.request.userdata = x++;
		req.send();
	}
}

function rresultHandleMods(r) {
	var rec = r.getResultObject();
	runEvt('result', 'recordReceived', rec, r.userdata, false);
	resultCollectCopyCounts(rec, r.userdata, FETCH_R_COPY_COUNTS);
	if(resultPageIsDone()) {
		runEvt('result', 'allRecordsReceived', recordsCache);
		unHideMe($('copyright_block')); 
	}
}


function rresultLaunchDrawn(id, node) {
	runEvt("rresult", "recordDrawn", id, node);
}


function rresultDoRecordSearch() { 
	resultCollectSearchIds(true, SEARCH_RS, rresultFilterSearchResults ); }
function rresultDoRecordMultiSearch() { 
	resultCollectSearchIds(false, SEARCH_RS, rresultFilterSearchResults ); }

/*
function _rresultCollectSearchIds( type ) {

	var sort		= (getSort() == SORT_TYPE_REL) ? null : getSort(); 
	var sortdir = (sort) ? ((getSortDir()) ? getSortDir() : SORT_DIR_ASC) : null;

	var form = parseForm(getForm());
	var item_type = form.item_type;
	var item_form = form.item_form;

	var args = {};

	if( type ) {
		args.searches = {};
		args.searches[getRtype()] = {};
		args.searches[getRtype()].term = getTerm();
	} else {
		args.searches = JSON2js(getAdvTerm());
	}

	args.org_unit = getLocation();
	args.depth    = getDepth();
	args.limit    = rresultLimit;
	args.offset   = getOffset();

	if(sort) args.sort = sort;
	if(sortdir) args.sort_dir = sortdir;
	if(item_type) args.item_type	= item_type;
	if(item_form) args.item_form	= item_form;

	var req = new Request(SEARCH_RS, args);
	req.callback(rresultFilterSearchResults);
	req.send();
}
*/


function rresultFilterSearchResults(r) {
	var result = r.getResultObject();
	var ids = [];
	for( var i = 0; i != result.ids.length; i++ ) 
		ids.push(result.ids[i][0]);
	_rresultHandleIds( ids, result.count );
}



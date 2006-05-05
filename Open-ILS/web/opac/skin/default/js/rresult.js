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

		case RTYPE_MRID :
		case null :
		case "" :
		defaut:
			var form = (getForm() == "all") ? null : getForm();
			var req = new Request(FETCH_RIDS, getMrid(), 
				{ format : form, org : getLocation(), depth : getDepth() } );
			req.callback( rresultHandleRIds );
			req.send();
	}
}


function rresultCollectMARCIds() {

	var args			= {};
	args.searches	= JSON2js(getSearches());
	args.limit		= 200;
	args.org_unit	= globalOrgTree.id();
	args.depth		= 0;

	var req = new Request(FETCH_ADV_MARC_MRIDS, args);
	req.callback(rresultHandleRIds);
	req.send();
}

function rresultHandleList() {
	var ids = new CGI().param(PARAM_RLIST);
	if(ids) _rresultHandleIds(ids, ids.length);
}

function rresultHandleRIds(r) {
	var res = r.getResultObject();
	_rresultHandleIds(res.ids, res.count);
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



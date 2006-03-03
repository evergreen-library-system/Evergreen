var records = new Array();
var table;
var rowtemplate;
var rresultLimit = 200;

function rresultUnload() { removeChildren(table); table = null;}

attachEvt("common", "unload", rresultUnload);
attachEvt("common", "run", rresultDoSearch);
attachEvt("result", "idsReceived", rresultCollectRecords); 
attachEvt("result", "recordDrawn", rresultLaunchDrawn); 

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

		case RTYPE_LIST :
			rresultHandleList();
			break;

		case RTYPE_MRID :
		defaut:
			var form = (getForm() == "all") ? null : getForm();
			var req = new Request(FETCH_RIDS, getMrid(), form );
			req.callback( rresultHandleRIds );
			req.send();
	}
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
	if(resultPageIsDone())  
		runEvt('result', 'allRecordsReceived', recordsCache);
}


function rresultLaunchDrawn(id, node) {
	runEvt("rresult", "recordDrawn", id, node);
}


function rresultDoRecordSearch() {

	var form		= (!getForm() || getForm() == "all") ? null : getForm();
	var sort		= (getSort() == SORT_TYPE_REL) ? null : getSort(); 
	var sortdir = (sort) ? ((getSortDir()) ? getSortDir() : SORT_DIR_ASC) : null;

	var req = new Request(FETCH_SEARCH_RIDS, getRtype(), 
		{	term		: getTerm(), 
			sort		: sort,
			sort_dir	: sortdir,
			org_unit : getLocation(),
			depth		: getDepth(),
			limit		: rresultLimit,
			offset	: getOffset(),
			format	: form } );

	req.callback(rresultFilterSearchResults);
	req.send();
}

function rresultFilterSearchResults(r) {
	var result = r.getResultObject();
	var ids = [];
	for( var i = 0; i != result.ids.length; i++ ) 
		ids.push(result.ids[i][0]);
	_rresultHandleIds( ids, result.count );
}



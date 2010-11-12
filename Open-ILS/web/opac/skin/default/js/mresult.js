//var records = {};
var records = [];
var ranks = [];
var onlyrecord = {};
var table;
var mresultPreCache = 200;
var searchTimer;
var resultFacetKey;

attachEvt("common", "unload", mresultUnload);
attachEvt("common", "run", mresultDoSearch);
attachEvt("result", "idsReceived", mresultSetRecords); 
attachEvt("result", "idsReceived", mresultCollectRecords); 

function mresultUnload() { removeChildren(table); table = null;}

hideMe($('copyright_block')); 

function mresultDoSearch() {


	TFORM = null; /* clear the rresult tform var so it's not propogated */

	swapCanvas($('loading_alt'));
	table = G.ui.result.main_table;

	while( table.parentNode.rows.length <= (getDisplayCount() + 1) )  
		table.appendChild(G.ui.result.row_template.cloneNode(true));

	if( (getSearches() || getAdvTerm()) && !getTerm() ) {
		if(getAdvType() == ADVTYPE_MULTI ) mresultCollectAdvIds();

	} else {
		_mresultCollectIds(); 
		ADVTERM = "";
		ADVTYPE = "";
	}
}

function _mresultCollectIds() { 
	resultCollectSearchIds(true, SEARCH_MRS_QUERY, mresultHandleMRIds ); 
}

function mresultCollectAdvIds() { 
	resultCollectSearchIds(false, SEARCH_MRS_QUERY, mresultHandleMRIds ); 
}

function mresultHandleMRIds(r) {
	var res = r.getResultObject();
    resultFacetKey = res.facet_key;
    resultCompiledSearch = res.compiled_search;
    dojo.require('dojo.cookie');
    dojo.cookie(COOKIE_SEARCH, js2JSON(res.compiled_search));
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

		/* wait at most 10 seconds for the mods rec to come back */
		/* this needs more testing  */
		req.request.timeout(10); 
		req.request.abortCallback(
			function(){
				recordsHandled++;
				if(resultPageIsDone()) {
					runEvt('result', 'allRecordsReceived', recordsCache);
					unHideMe($('copyright_block'));
				}
			}
		);

		req.callback(mresultHandleMods);
		req.send();
	}
}

function mresultHandleMods(r) {
	var rec = r.getResultObject();
	var pagePosition = r.userdata;
	runEvt('result', 'recordReceived', rec, pagePosition, true);
	if(rec) resultCollectCopyCounts(rec, pagePosition, FETCH_MR_COPY_COUNTS);
	if(resultPageIsDone()) {
		runEvt('result', 'allRecordsReceived', recordsCache);
		unHideMe($('copyright_block')); /* *** */
	}
}





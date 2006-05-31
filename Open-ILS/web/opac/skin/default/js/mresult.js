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

	swapCanvas($('loading_alt'));
	table = G.ui.result.main_table;

	while( table.parentNode.rows.length <= (getDisplayCount() + 1) )  
		table.appendChild(G.ui.result.row_template.cloneNode(true));

	if( (getSearches() || getAdvTerm()) && !getTerm() ) {
		if(getAdvType() == ADVTYPE_MULTI ) mresultCollectAdvIds();
		/*
		if(getAdvType() == ADVTYPE_MARC ) mresultCollectAdvMARCIds();
		*/

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

function _mresultCollectIds() { 
	if(getOffset() != 0 && mresultTryCachedSearch()) return; 
	resultCollectSearchIds(true, SEARCH_MRS, mresultHandleMRIds ); 
}

function mresultCollectAdvIds() { 
	if(getOffset() != 0 && mresultTryCachedSearch()) return; 
	resultCollectSearchIds(false, SEARCH_MRS, mresultHandleMRIds ); 
}

/*
function mresultCollectAdvMARCIds() {
	if(!mresultTryCachedSearch()) {
		var form = (getForm() == "all") ? null : getForm();
		var req = new Request(FETCH_ADV_MARC_MRIDS, 
			JSON2js(getAdvTerm()), getLocation(), form );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}
*/


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

		/* wait at most 15 seconds for the mods rec to come back */
		/* this needs more testing  */
		req.request.timeout(15); 
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





var records = {};
var ranks = {};
var table;
var rowtemplate;
var idsCookie = new cookieObject("ids", 1, "/", COOKIE_IDS);

function mresultUnload() { removeChildren(table); table = null;}

function mresultDoSearch() {

	table = G.ui.result.main_table;

	hideMe(G.ui.result.row_template);
	while( table.parentNode.rows.length <= getDisplayCount() )  /* add an extra so IE and safari won't complain */
		hideMe(table.appendChild(G.ui.result.row_template.cloneNode(true)));

	if(getOffset() == 0 || getHitCount() == null ) {
		mresultGetCount(); /* get the hit count */
		mresultCollectIds(); /* do the actual search */
	} else { 
		resultSetInfo();
		mresultCollectIds();
	}
}

function mresultGetCount() {
	var req = new Request(FETCH_MRCOUNT, 
			getStype(), getTerm(), getLocation(), getDepth(), getForm() );
	req.callback(mresultHandleCount);
	req.send();
}

function mresultHandleCount(r) {
	HITCOUNT = parseInt(r.getResultObject());
	resultSetInfo(); 
}


/* performs the actual search */
function mresultCollectIds() {


	if(getOffset() == 0) {
		idsCookie.put(COOKIE_IDS,"");
		idsCookie.write();
	} else {
		var c = JSON2js(idsCookie.get(COOKIE_IDS));
		if(c && c.recs) { records = c.recs; ranks = c.ranks; } 
	}

	if(	getOffset() != 0 && 
			records[getOffset()] != null && 
			records[resultFinalPageIndex()] != null) {
			mresultCollectRecords(); 

	} else {

		var req = new Request(FETCH_MRIDS, getStype(), getTerm(), 
			getLocation(), getDepth(), getDisplayCount() * 5, getOffset(), getForm() );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}

function mresultHandleMRIds(r) {
	mresultSetRecords(r.getResultObject().ids);
	mresultCollectRecords(); 
}

function mresultSetRecords(idstruct) {
	var o = getOffset();
	for( var x = o; x < idstruct.length + o; x++ ) {
		if(idstruct[x-o] == null) break;
		records[x] = parseInt(idstruct[x - o][0]);
		ranks[x] = parseFloat(idstruct[x - o][1]);
	}
	idsCookie.put(COOKIE_IDS, js2JSON({ recs: records, ranks : ranks }) );
	idsCookie.write();
}

function mresultHandleMods(r) {
	var rec = r.getResultObject();
	resultDisplayRecord(rec, rowtemplate, r.userdata, true);
	resultCollectCopyCounts(rec, FETCH_MR_COPY_COUNTS);
}


function mresultCollectRecords() {
	var i = 0;
	for( var x = getOffset(); x!= getDisplayCount() + getOffset(); x++ ) {
		if(isNull(records[x])) break;
		var req = new Request(FETCH_MRMODS, records[x]);
		req.request.userdata = i++;
		req.callback(mresultHandleMods);
		req.send();
	}
}



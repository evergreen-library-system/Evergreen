var records = {};
var ranks = {};
var table;
var rowtemplate;
var idsCookie = new cookieObject("ids", 1, "/", COOKIE_IDS);

attachEvt("common", "unload", mresultUnload);
attachEvt("common", "run", mresultDoSearch);
attachEvt("mresult", "idsReceived", mresultSetRecords); 
attachEvt("mresult", "idsReceived", mresultCollectRecords); 


function mresultUnload() { removeChildren(table); table = null;}

function mresultDoSearch() {

	table = G.ui.result.main_table;

	hideMe(G.ui.result.row_template);
	while( table.parentNode.rows.length <= getDisplayCount() )  /* add an extra row so IE and safari won't complain */
		hideMe(table.appendChild(G.ui.result.row_template.cloneNode(true)));

	if(getOffset() == 0 || getHitCount() == null ) {
	//	mresultGetCount(); 
		mresultCollectIds(FETCH_MRIDS_FULL); 
	} else { 
		runEvt('result', 'hitCountReceived');
		mresultCollectIds(FETCH_MRIDS);
	}
}

function mresultGetCount() {
	var form = (getForm() == "all") ? null : getForm();
	var req = new Request(FETCH_MRCOUNT, 
			getStype(), getTerm(), getLocation(), getDepth(), form );
	req.callback(mresultHandleCount);
	req.send();
}

function mresultHandleCount(r) {
	HITCOUNT = parseInt(r.getResultObject());
	runEvt('result', 'hitCountReceived');
}


/* performs the actual search */
function mresultCollectIds(method) {

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

		var req = new Request(method, getStype(), getTerm(), 
			getLocation(), getDepth(), getDisplayCount() * 10, getOffset(), getForm() );
		req.callback(mresultHandleMRIds);
		req.send();
	}
}

function mresultHandleMRIds(r) {
	var res = r.getResultObject();

	if(res.count != null) {
		HITCOUNT = res.count;
		runEvt('result', 'hitCountReceived');
	} 
	runEvt('mresult', 'idsReceived', res.ids);
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

function mresultHandleMods(r) {
	var rec = r.getResultObject();
	var pagePosition = r.userdata;
	runEvt('result', 'recordReceived', rec, pagePosition, true);
	resultCollectCopyCounts(rec, pagePosition, FETCH_MR_COPY_COUNTS);
}



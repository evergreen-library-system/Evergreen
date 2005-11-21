//var records = {};
var records = [];
var ranks = [];
var onlyrecord = {};
var table;
var mresultPreCache = 200;
//var idsCookie = new cookieObject("ids", 1, "/", COOKIE_IDS);
//var idsCookie;
var idsCookie = new HTTP.Cookies();
var searchTimer;

attachEvt("common", "unload", mresultUnload);
attachEvt("common", "run", mresultDoSearch);
attachEvt("result", "idsReceived", mresultSetRecords); 
attachEvt("result", "idsReceived", mresultCollectRecords); 


function mresultUnload() { removeChildren(table); table = null;}

function mresultDoSearch() {
	//idsCookie = new HTTP.Cookies();

	if(getOffset() == 0) {
		swapCanvas($('loading_alt'));
		searchTimer = new Timer('searchTimer',$('loading_alt_span'));
		searchTimer.start();
	}

	table = G.ui.result.main_table;

	while( table.parentNode.rows.length <= (getDisplayCount() + 1) )  /* add an extra row so IE and safari won't complain */
		table.appendChild(G.ui.result.row_template.cloneNode(true));

	if(getOffset() == 0 || getHitCount() == null ) 
		mresultCollectIds(FETCH_MRIDS_FULL); 
	else  
		mresultCollectIds(FETCH_MRIDS);
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

	if( (getOffset() > 0) && (getOffset() < mresultPreCache) ) {
		//alert('cached: ' + idsCookie.read(COOKIE_IDS));
		var c = JSON2js(idsCookie.read(COOKIE_IDS));
		if(c) { records = c[0]; ransk = c[1]; }
	}

	if(	getOffset() != 0 && 
			records[getOffset()] != null && 
			records[resultFinalPageIndex()] != null) {
			//alert('we have cookies...  offset : ' + getOffset() );
			runEvt('result', 'hitCountReceived');
			mresultCollectRecords(); 

	} else {

		var form = (getForm() == "all") ? null : getForm();
		var req = new Request(method, getStype(), getTerm(), 
			getLocation(), getDepth(), mresultPreCache, getOffset(), form );
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
		idsCookie.remove(COOKIE_IDS);
		idsCookie.write(COOKIE_IDS, js2JSON([ records, ranks ]), '+1d' );
		//alert('Set cookies: ' + idsCookie.read(COOKIE_IDS) + ' : ' + idsCookie.read(COOKIE_IDS).length );
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
}



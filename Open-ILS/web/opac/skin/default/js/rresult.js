var records = new Array();
var table;
var rowtemplate;

function rresultUnload() { removeChildren(table); table = null;}

attachEvt("common", "unload", rresultUnload);
attachEvt("common", "run", rresultDoSearch);
attachEvt("rresult", "idsReceived", rresultCollectRecords); 
attachEvt("result", "recordDrawn", rresultLaunchDrawn); 

function rresultDoSearch() {
	table = G.ui.result.main_table;
	hideMe(G.ui.result.row_template);
	while( table.parentNode.rows.length < getDisplayCount() ) 
		hideMe(table.appendChild(G.ui.result.row_template.cloneNode(true)));
	rresultCollectIds();
}

function rresultCollectIds() {
	var form = (getForm() == "all") ? null : getForm();
	var req = new Request(FETCH_RIDS, getMrid(), form );
	req.callback( rresultHandleRIds );
	req.send();
}

function rresultHandleRIds(r) {
	var res = r.getResultObject();
	HITCOUNT = parseInt(res.count);
	runEvt('result', 'hitCountReceived');
	runEvt('rresult', 'idsReceived', res.ids);
}

function rresultCollectRecords(ids) {
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
}


function rresultLaunchDrawn(id, node) {
	runEvt("rresult", "recordDrawn", id, node);
}

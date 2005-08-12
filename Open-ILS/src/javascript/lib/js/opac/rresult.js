var records = new Array();
var table;
var rowtemplate;

function rresultUnload() { removeChildren(table); table = null;}

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
	resultSetInfo();
	rresultCollectRecords(res.ids);
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
	resultDisplayRecord(rec, rowtemplate, r.userdata, false);
	resultCollectCopyCounts(rec, FETCH_R_COPY_COUNTS);
}


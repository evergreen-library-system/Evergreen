var records = new Array();
var table;
var rowtemplate;

function rresultDoSearch() {
	table = G.ui.result.main_table;
	rowtemplate = table.removeChild(G.ui.result.row_template);
	removeChildren(table);
	rresultCollectIds();
}

function rresultCollectIds() {
	var req = new Request(FETCH_RIDS, getMrid(), getForm() );
	req.callback( function(r) {
		var res = r.getResultObject();
		HITCOUNT = parseInt(res.count);
		resultSetInfo();
		rresultCollectRecords(res.ids); });
	req.send();
}

function rresultCollectRecords(ids) {
	for( var i = getOffset(); i!= getDisplayCount() + getOffset(); i++ ) {
		var req = new Request(FETCH_RMODS, parseInt(ids[i]));
		req.callback( function(r) {
			var rec = r.getResultObject();
			resultDisplayRecord(rec, rowtemplate, false);
			resultCollectCopyCounts(rec, FETCH_R_COPY_COUNTS);
		});
		req.send();
	}
}


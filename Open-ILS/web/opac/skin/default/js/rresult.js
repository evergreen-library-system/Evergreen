var records = new Array();
var table;
var rowtemplate;

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

		case RTYPE_MRID :
		defaut:
			var form = (getForm() == "all") ? null : getForm();
			var req = new Request(FETCH_RIDS, getMrid(), form );
			req.callback( rresultHandleRIds );
			req.send();
	}
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
}


function rresultLaunchDrawn(id, node) {
	runEvt("rresult", "recordDrawn", id, node);
}

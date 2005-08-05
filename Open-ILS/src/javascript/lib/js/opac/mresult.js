var records = new Array();
var ranks = new Array();
var table;
var rowtemplate;

function mresultDoSearch() {

	table = G.ui.result.main_table;
	rowtemplate = table.removeChild(G.ui.result.row_template);
	removeChildren(table);

	if(getOffset() == 0 || getHitCount() == null ) {
		mresultGetCount();
		mresultCollectIds();
	} else { 
		resultSetInfo();
		mresultCollectIds();
	}
}

function mresultGetCount() {
	var req = new Request(FETCH_MRCOUNT, 
			getStype(), getTerm(), getLocation(), getDepth(), getForm() );
	req.callback( function(r) {
		HITCOUNT = parseInt(r.getResultObject());
		resultSetInfo(); });
	req.send();
}


/* performs the actual search */
function mresultCollectIds() {
	var req = new Request(FETCH_MRIDS, getStype(), getTerm(), 
			getLocation(), getDepth(), getDisplayCount(), getOffset(), getForm() );
	req.callback( function(r) {
		mresultSetRecords(r.getResultObject().ids);
		mresultCollectRecords(); 
		req.request = null;
		r.callback = null;
	});
	req.send();
}

function mresultSetRecords(idstruct) {
	var o = getOffset();
	for( var x = o; x!= idstruct.length + o; x++ ) {
		records[x] = idstruct[x - o][0];
		ranks[x] = idstruct[x - o][1];
	}
}


function mresultCollectRecords() {
	for( var x = getOffset(); x!= getDisplayCount() + getOffset(); x++ ) {
		if(isNull(records[x])) break;

		var req = new Request(FETCH_MRMODS, records[x]);
		req.callback(function(r){
				var rec = r.getResultObject();
				resultDisplayRecord(rec, rowtemplate, true);
				mresultCollectCopyCounts(rec);
		});
		req.send();

		/*		
		if( x == (getDisplayCount() + getOffset()) - 1 ) {
			G.ui.result.top_div.appendChild(
				G.ui.result.nav_links.cloneNode(true));
		}
		*/
	}
}

function mresultCollectCopyCounts(rec) {
	if(rec == null) return;
	if(rec.doc_id() == null) return;

	var req = new Request(FETCH_MR_COPY_COUNTS, getLocation(), rec.doc_id() );
	req.callback(function(r){ mresultDisplayCopyCounts(rec, r.getResultObject()); });
	req.send();
}

function mresultDisplayCopyCounts(rec, copy_counts) {
	if(copy_counts == null || rec == null) return;
	var i = 0;
	while(copy_counts[i] != null) {
		var cell = getId("copy_count_cell_" + i +"_" + rec.doc_id());
		cell.appendChild(text(copy_counts[i].available + " / " + copy_counts[i].count));
		i++;
	}
}




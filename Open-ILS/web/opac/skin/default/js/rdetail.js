/* */
attachEvt("common", "run", rdetailDraw);
attachEvt("rdetail", "recordDrawn", rdetailBuildStatusColumns);
attachEvt("rdetail", "recordDrawn", rdetailBuildInfoRows);

var record = null;
var cp_statuses = null;

function rdetailDraw() {

	G.ui.rdetail.cp_info_local.onclick = rdetailShowLocalCopies;
	G.ui.rdetail.cp_info_all.onclick = rdetailShowAllCopies;
	var req = new Request(FETCH_RMODS, getRid());
	req.callback(_rdetailDraw);
	req.send();
}

function rdetailShowLocalCopies() {
	var rows = getId("first_copy_info_row").parentNode.getElementsByTagName("tr");
	var found = false;
	for( var r in rows ) {
		if(r == 0) continue;
		hideMe(rows[r]);
		if(!isNull(rows[r]) && rows[r].getAttribute && 
			rows[r].getAttribute("local")) {
			unHideMe(rows[r]);
			found = true;
		}
	}
	if(!found) unHideMe(G.ui.rdetail.cp_info_none);
	hideMe(G.ui.rdetail.cp_info_local);
	unHideMe(G.ui.rdetail.cp_info_all);
}

function rdetailShowAllCopies() {
	var rows = getId("first_copy_info_row").parentNode.getElementsByTagName("tr");
	for( var r in rows ) unHideMe(rows[r]);
	hideMe(G.ui.rdetail.cp_info_all);
	unHideMe(G.ui.rdetail.cp_info_local);
	hideMe(G.ui.rdetail.cp_info_none);
}


function _rdetailDraw(r) {
	record = r.getResultObject();

	G.ui.rdetail.title.appendChild(text(record.title()));
	G.ui.rdetail.author.appendChild(text(record.author()));
	G.ui.rdetail.isbn.appendChild(text(cleanISBN(record.isbn())));
	G.ui.rdetail.edition.appendChild(text(record.edition()));
	G.ui.rdetail.pubdate.appendChild(text(record.pubdate()));
	G.ui.rdetail.publisher.appendChild(text(record.publisher()));
	G.ui.rdetail.tor.appendChild(text(record.types_of_resource()));
	G.ui.rdetail.abstr.appendChild(text(record.synopsis()));

	G.ui.rdetail.image.setAttribute("src", buildISBNSrc(cleanISBN(record.isbn())));
	runEvt("rdetail", "recordDrawn");
}

var _statusPositions = {};
function rdetailBuildStatusColumns() {

	rdetailGrabCopyStatuses();
	var parent = G.ui.rdetail.cp_status.parentNode;
	var template = parent.removeChild(G.ui.rdetail.cp_status);

	var i = 0;
	for( i = 0; i < cp_statuses.length; i++ ) {
		var c = cp_statuses[i];
		if(c && c.holdable()) {
			_statusPositions[i] = c;
			var node = template.cloneNode(true);
			node.appendChild(text("#" + c.name()));
			parent.appendChild(node);
		}	
	}	
}

function rdetailBuildInfoRows() {
	var req = new Request(FETCH_COPY_COUNTS_SUMMARY, record.doc_id())
	req.callback(_rdetailBuildInfoRows);
	req.send();
}

function _rdetailSortSummary(a,b) {
	a = findOrgUnit(a[0]).name().toLowerCase();
	b = findOrgUnit(b[0]).name().toLowerCase();
	if(a<b) return -1;
	if(a>b) return 1;
	return 0;
}

function _rdetailBuildInfoRows(r) {

	var summary = r.getResultObject();

	var curLoc = getLocation();

	summary = summary.sort(_rdetailSortSummary);

	/* remove the 'now loading' thingy */
	G.ui.rdetail.cp_info_loading.parentNode.removeChild(
		G.ui.rdetail.cp_info_loading);

	var parent = G.ui.rdetail.cp_info_row.parentNode;
	var template = parent.removeChild(G.ui.rdetail.cp_info_row);

	var found = false;
	for( var i = 0; i != summary.length; i++ ) {

		var arr = summary[i];
		var node = template.cloneNode(true);
		if(i == 0) node.id = "first_copy_info_row";
		if(parseInt(arr[0]) != curLoc)  hideMe(node); 
		else {found = true; node.setAttribute("local", "1");}

		if(i%2) addCSSClass(node, config.css.color_3);
		var lib = findNodeByName(node, config.names.rdetail.lib_cell);
		var cn = findNodeByName(node, config.names.rdetail.cn_cell);
		var tdtemplate = node.removeChild(findNodeByName(node, config.names.rdetail.cp_count_cell));

		lib.appendChild(text(findOrgUnit(arr[0]).name()));
		cn.appendChild(text(arr[1]));
		parent.appendChild(node);

		for( var j in _statusPositions ) {
			var stat = _statusPositions[j];
			var val = arr[2][stat.id()];
			var nn = tdtemplate.cloneNode(true);
			if(val) nn.appendChild(text(val));
			else nn.appendChild(text(0));
			node.appendChild(nn);	
		}
	}
	if(!found) unHideMe(G.ui.rdetail.cp_info_none);
}


function _rdetailSortStatuses(a, b) {
	return parseInt(a.id()) - parseInt(b.id());
}


function rdetailGrabCopyStatuses() {
	if(cp_statuses) return cp_statuses;
   var req = new Request(FETCH_COPY_STATUSES);
   req.send(true);
	cp_statuses = req.result();
	cp_statuses = cp_statuses.sort(_rdetailSortStatuses);
}





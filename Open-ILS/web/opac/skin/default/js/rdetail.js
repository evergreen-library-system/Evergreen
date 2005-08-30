/* */
attachEvt("common", "run", rdetailDraw);
attachEvt("rdetail", "recordDrawn", rdetailBuildStatusColumns);
attachEvt("rdetail", "recordDrawn", rdetailBuildInfoRows);

var record = null;
var cp_statuses = null;

var copyRowParent = null;
var copyRow = null;
var statusRow = null;

function rdetailDraw() {

	copyRowParent = G.ui.rdetail.cp_info_row.parentNode;
	copyRow = copyRowParent.removeChild(G.ui.rdetail.cp_info_row);
	statusRow = G.ui.rdetail.cp_status.parentNode;
	statusRow.id = '__rdsrow';

	G.ui.rdetail.cp_info_local.onclick = rdetailShowLocalCopies;
	G.ui.rdetail.cp_info_all.onclick = rdetailShowAllCopies;
	var req = new Request(FETCH_RMODS, getRid());
	req.callback(_rdetailDraw);
	req.send();
}

function rdetailShowLocalCopies() {

	var found = false;
	var rows = copyRowParent.getElementsByTagName("tr");
	for( var r in rows ) {
		if(rows[r].id == "__rdsrow") continue;
		hideMe(rows[r]);
		if(rows[r].getAttribute && rows[r].getAttribute("local")) {
			unHideMe(rows[r]);
			found = true;
		}
	}

	if(!found) unHideMe(G.ui.rdetail.cp_info_none);
	hideMe(G.ui.rdetail.cp_info_local);
	unHideMe(G.ui.rdetail.cp_info_all);
}

function rdetailShowAllCopies() {
	var rows = copyRowParent.getElementsByTagName("tr");
	for( var r in rows ) 
		if(rows[r].getAttribute && rows[r].getAttribute("hasinfo"))
			unHideMe(rows[r]);

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



function rdetailBuildInfoRows() {
	var req = new Request(FETCH_COPY_COUNTS_SUMMARY, record.doc_id())
	req.callback(_rdetailBuildInfoRows);
	req.send();
}

/* pre-allocate the copy info table with all org units */
function _rdetailRows(node) {

	if(node) {

		var row = copyRow.cloneNode(true);
		row.id = "cp_info_" + node.id();
		var libtd = findNodeByName( row, config.names.rdetail.lib_cell );
		var cntd = findNodeByName( row, config.names.rdetail.cn_cell );
		var cpctd = findNodeByName( row, config.names.rdetail.cp_count_cell );
	
		libtd.appendChild(text(node.name()));
		libtd.setAttribute("style", "padding-left: " + ((findOrgDepth(node) - 1)  * 9) + "px;");
	
		if(!findOrgType(node.ou_type()).can_have_vols()) {
			var c = 2;
			for(x in _statusPositions) c++;
			libtd.setAttribute("colspan", c );
			libtd.colSpan = c;
			row.removeChild(cntd);
			row.removeChild(cpctd);
			addCSSClass(row, config.css.color_3);
		} 
	
		copyRowParent.appendChild(row);

	} else { node = globalOrgTree; }

	for( var c in node.children() ) 
		_rdetailRows(node.children()[c]);
}

/* walk through the copy info and build rows where necessary */
function _rdetailBuildInfoRows(r) {

	_rdetailRows();

	var summary = r.getResultObject();
	var curLoc = getLocation();

	/* remove the 'now loading' thingy */
	G.ui.rdetail.cp_info_loading.parentNode.removeChild(
		G.ui.rdetail.cp_info_loading);

	var curLoc = getLocation();

	for( var i = 0; i < summary.length; i++ ) {

		var arr = summary[i];
		var rowNode = copyRow.cloneNode(true);
		var rowNode = getId("cp_info_" + arr[0]);


		if(rowNode.getAttribute("used")) {

			if( rowNode.nextSibling )
				rowNode = copyRowParent.insertBefore(copyRow.cloneNode(true), rowNode.nextSibling);
			else
				rowNode = copyRowParent.appendChild(copyRow.cloneNode(true));
			var n = findNodeByName( rowNode, config.names.rdetail.lib_cell );
			n.appendChild(text(findOrgUnit(arr[0]).name()));
			n.setAttribute("style", "padding-left: " + ((findOrgDepth(arr[0]) - 1)  * 9) + "px;");

		} else {
			rowNode.setAttribute("used", "1");
		}

		rowNode.setAttribute("hasinfo", "1");
		var p = getId("cp_info_" + findOrgUnit(arr[0]).parent_ou());
		if(p) p.setAttribute("hasinfo", "1");

		if( orgIsMine( findOrgUnit(curLoc), findOrgUnit(arr[0]) ) ) {
			unHideMe(rowNode);
			unHideMe(getId("cp_info_" + findOrgUnit(arr[0]).parent_ou()));
			rowNode.setAttribute("local", "1");
		}

		var cntd = findNodeByName( rowNode, config.names.rdetail.cn_cell );
		cntd.appendChild(text(arr[1]));
		var cpc_temp = rowNode.removeChild(findNodeByName(rowNode, config.names.rdetail.cp_count_cell));

		for( var j in _statusPositions ) {
			var stat = _statusPositions[j];
			var val = arr[2][stat.id()];
			var nn = cpc_temp.cloneNode(true);
			if(val) nn.appendChild(text(val));
			else nn.appendChild(text(0));
			rowNode.appendChild(nn);	
		}

	}

	/* unhide the path to me */
	var nodeTrail = orgNodeTrail(findOrgUnit(curLoc));
	for( var i = 0; i != nodeTrail.length; i++ ) {
		var n = getId("cp_info_" + nodeTrail[i].id());
		if(n) {
			unHideMe(n);
			n.setAttribute("local", "1");
		}
	}
}



/* --------------------------------------------------------------------- */
var _statusPositions = {};

function rdetailBuildStatusColumns() {

	rdetailGrabCopyStatuses();
	var parent = statusRow;
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

function rdetailGrabCopyStatuses() {
	if(cp_statuses) return cp_statuses;
   var req = new Request(FETCH_COPY_STATUSES);
   req.send(true);
	cp_statuses = req.result();
	cp_statuses = cp_statuses.sort(_rdetailSortStatuses);
}

function _rdetailSortStatuses(a, b) {
	return parseInt(a.id()) - parseInt(b.id());
}



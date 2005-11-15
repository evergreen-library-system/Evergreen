/* */

attachEvt("common", "run", rdetailDraw);
attachEvt("rdetail", "recordDrawn", rdetailBuildStatusColumns);
attachEvt("rdetail", "recordDrawn", rdetailBuildInfoRows);

var record = null;
var cp_statuses = null;
var recordsCache = [];

var copyRowParent = null;
var copyRow = null;
var statusRow = null;
var numStatuses = null;

function rdetailDraw() {

	copyRowParent = G.ui.rdetail.cp_info_row.parentNode;
	copyRow = copyRowParent.removeChild(G.ui.rdetail.cp_info_row);
	statusRow = G.ui.rdetail.cp_status.parentNode;
	statusRow.id = '__rdsrow';

	G.ui.rdetail.cp_info_local.onclick = rdetailShowLocalCopies;
	G.ui.rdetail.cp_info_all.onclick = rdetailShowAllCopies;
	G.ui.rdetail.view_marc.onclick = rdetailViewMarc;
	G.ui.rdetail.hide_marc.onclick = showCanvas;


	if(getLocation() == globalOrgTree.id())
		hideMe(G.ui.rdetail.cp_info_all);



	var req = new Request(FETCH_RMODS, getRid());
	req.callback(_rdetailDraw);
	req.send();
}

function rdetailViewMarc() {
	if(!record) return;

	if( G.ui.rdetail.view_marc_box.innerHTML.indexOf("style") == -1 ) {
		var req = new Request( FETCH_MARC_HTML, record.doc_id() );
		req.send(true);
		var html = req.result();
		G.ui.rdetail.view_marc_box.innerHTML = html;
	}
	swapCanvas(G.ui.rdetail.view_marc_div);
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
	buildSearchLink(STYPE_AUTHOR, record.author(), G.ui.rdetail.author);
	G.ui.rdetail.isbn.appendChild(text(cleanISBN(record.isbn())));
	G.ui.rdetail.edition.appendChild(text(record.edition()));
	G.ui.rdetail.pubdate.appendChild(text(record.pubdate()));
	G.ui.rdetail.publisher.appendChild(text(record.publisher()));
	G.ui.rdetail.tor.appendChild(text(record.types_of_resource()[0]));
	setResourcePic( G.ui.rdetail.tor_pic, record.types_of_resource()[0]);
	G.ui.rdetail.abstr.appendChild(text(record.synopsis()));


	$('rdetail_place_hold').setAttribute(
		'href','javascript:holdsDrawWindow("'+record.doc_id()+'");');

	G.ui.rdetail.image.setAttribute("src", buildISBNSrc(cleanISBN(record.isbn())));
	runEvt("rdetail", "recordDrawn");
	recordsCache.push(record);
}


function rdetailBuildInfoRows() {
	var req = new Request(FETCH_COPY_COUNTS_SUMMARY, record.doc_id())
	req.callback(_rdetailBuildInfoRows);
	req.send();
}

/* pre-allocate the copy info table with all org units in correct order */
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

			row.removeChild(cntd);
			row.removeChild(cpctd);

			libtd.setAttribute("colspan", numStatuses + 2 );
			libtd.colSpan = numStatuses + 2;
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

	G.ui.rdetail.cp_info_loading.parentNode.removeChild(
		G.ui.rdetail.cp_info_loading);

	var found = false;
	for( var i = 0; i < summary.length; i++ ) {

		var arr = summary[i];
		var thisOrg = findOrgUnit(arr[0]);
		var rowNode = $("cp_info_" + thisOrg.id());

		if(rowNode.getAttribute("used")) {

			if( rowNode.nextSibling )
				rowNode = copyRowParent.insertBefore(copyRow.cloneNode(true), rowNode.nextSibling);
			else
				rowNode = copyRowParent.appendChild(copyRow.cloneNode(true));
			var n = findNodeByName( rowNode, config.names.rdetail.lib_cell );
			n.appendChild(text(thisOrg.name()));
			n.setAttribute("style", "padding-left: " + ((findOrgDepth(thisOrg) - 1)  * 9) + "px;");

		} else rowNode.setAttribute("used", "1");

		findNodeByName( rowNode, config.names.rdetail.cn_cell ).appendChild(text(arr[1]));

		var cpc_temp = rowNode.removeChild(
			findNodeByName(rowNode, config.names.rdetail.cp_count_cell));

		rdetailApplyStatuses(rowNode, cpc_temp, arr[2]);

		var isLocal = false;
		if( orgIsMine( findOrgUnit(getLocation()), thisOrg ) ) { found = true; isLocal = true; }
		rdetailSetPath( thisOrg, isLocal );

	}

	if(!found) unHideMe(G.ui.rdetail.cp_info_none);

}

/* sets the path to org as 'active' and displays the 
	path if it's local */
function rdetailSetPath(org, local) {
	if( findOrgDepth(org) == 0 ) return;
	var row = $("cp_info_" + org.id());
	row.setAttribute("hasinfo", "1");
	if(local) {
		unHideMe(row);
		row.setAttribute("local", "1");
	}
	rdetailSetPath(findOrgUnit(org.parent_ou()), local);
}

function rdetailApplyStatuses( row, template, statuses ) {
	for( var j in _statusPositions ) {
		var stat = _statusPositions[j];
		var val = statuses[stat.id()];
		var nn = template.cloneNode(true);
		if(val) nn.appendChild(text(val));
		else nn.appendChild(text(0));
		row.appendChild(nn);	
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

			var name = c.name();
			_statusPositions[i] = c;
			var node = template.cloneNode(true);
			var data = findNodeByName( node, config.names.rdetail.cp_status);

			data.appendChild(text(name));
			parent.appendChild(node);
		}	
	}	

	numStatuses = 0;
	for(x in _statusPositions) numStatuses++; 
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



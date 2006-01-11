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
var defaultCN;
var callnumberCache = {};
var rdetailLocalOnly = true;

function rdetailDraw() {


	copyRowParent = G.ui.rdetail.cp_info_row.parentNode;
	copyRow = copyRowParent.removeChild(G.ui.rdetail.cp_info_row);
	statusRow = G.ui.rdetail.cp_status.parentNode;
	statusRow.id = '__rdsrow';

	G.ui.rdetail.cp_info_local.onclick = rdetailShowLocalCopies;
	G.ui.rdetail.cp_info_all.onclick = rdetailShowAllCopies;

	if(getLocation() == globalOrgTree.id())
		hideMe(G.ui.rdetail.cp_info_all);

	var req = new Request(FETCH_RMODS, getRid());
	req.callback(_rdetailDraw);
	req.send();
}

var rdeatilMarcFetched = false;
function rdetailViewMarc(r) {
	hideMe($('rdetail_extras_loading'));
	$('rdetail_view_marc_box').innerHTML = r.getResultObject();
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
	rdetailLocalOnly = true;
}

function rdetailShowAllCopies() {
	var rows = copyRowParent.getElementsByTagName("tr");
	for( var r in rows ) 
		if(rows[r].getAttribute && rows[r].getAttribute("hasinfo"))
			unHideMe(rows[r]);

	hideMe(G.ui.rdetail.cp_info_all);
	unHideMe(G.ui.rdetail.cp_info_local);
	hideMe(G.ui.rdetail.cp_info_none);
	rdetailLocalOnly = false;
}


function _rdetailDraw(r) {
	record = r.getResultObject();

	runEvt('rdetail', 'recordRetrieved', record.doc_id());

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

	rdetailSetExtrasSelector();

	var req = new Request(FETCH_ACONT_SUMMARY, cleanISBN(record.isbn()));
	req.callback(rdetailHandleAddedContent);
	req.send();

	resultBuildCaches( [ record ] );
	resultDrawSubjects();
	resultDrawSeries();
}

function rdetailSetExtrasSelector() {
	if(!grabUser()) return;
	unHideMe($('rdetail_more_actions'));


	var selector = $('rdetail_more_actions_selector');

	var req = new Request( 
		FETCH_CONTAINERS, G.user.session, G.user.id(), 'biblio', 'bookbag' );
	req.callback(rdetailAddBookbags);
	req.send();
}

function rdetailAddBookbags(r) {

	var containers = r.getResultObject();
	var selector = $('rdetail_more_actions_selector');
	var found = false;
	var index = 3;

	for( var i = 0; i != containers.length; i++ ) {
		found = true;
		var container = containers[i];
		insertSelectorVal( selector, index++, container.name(), 
			"container_" + container.id(), rdetailAddToBookbag, 1 );
	}

	if(!found) insertSelectorVal( selector, 3, "name", "value", 1 );
}

function rdetailAddToBookbag() {
	var selector = $('rdetail_more_actions_selector');
	var id = selector.options[selector.selectedIndex].value;
	alert(id);
	setSelector( selector, 'start' );
}



var rdetailTocFetched		= false;
var rdetailReviewFetched	= false;
var rdetailMarcFetched		= false;

function rdetailShowExtra(type) {

	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_marc_div'));
	hideMe($('cn_browse'));
	hideMe($('rdetail_cn_browse_div'));

	var req;
	switch(type) {
		case "copyinfo": 
			unHideMe($('rdetail_copy_info_div')); 
			break;

		case "reviews": 
			unHideMe($('rdetail_reviews_div')); 
			if(rdetailReviewFetched) break;
			unHideMe($('rdetail_extras_loading'));
			rdetailReviewFetched = true;
			req = new Request(FETCH_REVIEWS, cleanISBN(record.isbn()));
			req.callback(rdetailShowReviews);
			req.send();
			break;

		case "toc": 
			unHideMe($('rdetail_toc_div'));
			if(rdetailTocFetched) break;
			unHideMe($('rdetail_extras_loading'));
			rdetailTocFetched = true;
			var req = new Request(FETCH_TOC, cleanISBN(record.isbn()));
			req.callback(rdetailShowTOC);
			req.send();
			break;

		case "marc": 
			unHideMe($('rdetail_marc_div')); 
			if(rdetailMarcFetched) return;
			unHideMe($('rdetail_extras_loading'));
			rdetailMarcFetched = true;
			var req = new Request( FETCH_MARC_HTML, record.doc_id() );
			req.callback(rdetailViewMarc); 
			req.send();
			break;

		case 'cn':
			unHideMe($('rdetail_cn_browse_div'));
			rdetailShowCNBrowse(defaultCN, null, true);
			break;
	}
}

function rdetailBuildCNList() {
	var select = $('cn_browse_selector');
	var index = 0;
	for( var cn in callnumberCache ) {
		var opt = new Option(cn);
		opt.onclick = rdetailGatherCN;
		select.options[index++] = opt;
	}
}

function rdetailGatherCN() {
	var cn = getSelectorVal($('cn_browse_selector'));
	rdetailShowCNBrowse( cn, getDepth(), true );
	setSelector( $('cn_browse_selector'), cn );
}


function rdetailShowCNBrowse( cn, depth, fromOnclick ) {
	if(!cn) return;
	rdetailBuildCNList();
	setSelector( $('cn_browse_selector'), cn );
	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_marc_div'));
	unHideMe($('rdetail_cn_browse_div'));
	unHideMe($('cn_browse'));
	if( !rdetailLocalOnly && ! fromOnclick ) depth = findOrgDepth(globalOrgTree);
	cnBrowseGo(cn, depth);
}

function rdetailHandleAddedContent(r) {
	var resp = r.getResultObject();
	if( resp.Review == 'true' ) unHideMe($('rdetail_reviews_link'));
	if( resp.TOC == 'true' ) unHideMe($('rdetail_toc_link'));
}


function rdetailShowReviews(r) {
	hideMe($('rdetail_extras_loading'));
	var res = r.getResultObject();
	var par = $('rdetail_reviews_div');
	var template = par.removeChild($('rdetail_review_template'));
	if( res && res.length > 0 ) {
		unHideMe($('rdetail_reviews_link'));
		for( var i = 0; i != res.length; i++ ) {
			var rev = res[i];	
			if( rev.text && rev.info ) {
				var node = template.cloneNode(true);
				$n(node, 'review_header').appendChild(text(rev.info));
				$n(node, 'review_text').appendChild(text(rev.text));
				par.appendChild(node);
			}
		}
	}
}

function rdetailShowTOC(r) {
	hideMe($('rdetail_extras_loading'));
	var resp = r.getResultObject();
	if(resp) {
		unHideMe($('rdetail_toc_link'));
		$('rdetail_toc_div').innerHTML = resp;
	}
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
			addCSSClass(row, 'copy_info_region_row');
		} 
	
		copyRowParent.appendChild(row);

	} else { node = globalOrgTree; }

	for( var c in node.children() ) 
		_rdetailRows(node.children()[c]);
}

/* walk through the copy info and build rows where necessary */
var localCNFound = false;
function _rdetailBuildInfoRows(r) {

	_rdetailRows();

	var summary = r.getResultObject();
	if(!summary) return;

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

		var cpc_temp = rowNode.removeChild(
			findNodeByName(rowNode, config.names.rdetail.cp_count_cell));

		rdetailApplyStatuses(rowNode, cpc_temp, arr[2]);

		var isLocal = false;
		if( orgIsMine( findOrgUnit(getLocation()), thisOrg ) ) { 
			found = true; 
			isLocal = true; 
			if(!localCNFound) {
				localCNFound = true;
				defaultCN = arr[1];
			}
		}
		rdetailSetPath( thisOrg, isLocal );
		rdetailBuildBrowseInfo( rowNode, arr[1], isLocal );

		if( i == summary.length - 1 && !defaultCN) defaultCN = arr[1];
	}

	if(!found) unHideMe(G.ui.rdetail.cp_info_none);

}

function rdetailBuildBrowseInfo(row, cn, local) {
	/* used for building the shelf browser */
	if(local) {
		var cache = callnumberCache[cn];
		if( cache ) cache.count++;
		else callnumberCache[cn] = { count : 1 };
	}

	var depth = getDepth();
	if( !local ) depth = findOrgDepth(globalOrgTree);
	var a = elem("a", {href:'javascript:rdetailShowCNBrowse("' + cn + '", "'+depth+'");' }, cn);
	addCSSClass(a, 'classic_link');
	findNodeByName( row, config.names.rdetail.cn_cell ).appendChild(a);
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



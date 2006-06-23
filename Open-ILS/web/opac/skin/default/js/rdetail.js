/* */


detachAllEvt('common', 'run');
attachEvt("common", "run", rdetailDraw);
attachEvt("rdetail", "recordDrawn", rdetailBuildStatusColumns);
attachEvt("rdetail", "recordDrawn", rdetailBuildInfoRows);
attachEvt("rdetail", "recordDrawn", rdetailGetPageIds);

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
var globalCNCache	= {};
var localTOC;
var cachedRecords;

var rdetailShowLocal = true;



var nextContainerIndex;

function rdetailReload() {
	var args = {};
	args[PARAM_LOCATION] = getNewSearchLocation();
	args[PARAM_DEPTH] = depthSelGetDepth();
	goTo(buildOPACLink(args));
}

var nextRecord;
var prevRecord;

var rdetailPrev = null;
var rdetailNext = null;
var rdetailStart = null;
var rdetailEnd = null;



/* looks to see if we have a next and/or previous record in the
record cache, if so, set up the nav links */
function rdetailSetPaging(ids) {

	cachedRecords = {};
	cachedRecords.ids = ids;

	for( var i = 0; i < cachedRecords.ids.length; i++ ) {
		var rec = cachedRecords.ids[i];
		if( rec == getRid() ) {
			if( i > 0 ) prevRecord = cachedRecords.ids[i-1];
			if( i < cachedRecords.ids.length - 1 )
				nextRecord = cachedRecords.ids[i+1];
			break;
		}
	}

	$('np_offset').appendChild(text(i + 1));
	$('np_count').appendChild(text(getHitCount()));

	if(prevRecord) {
		unHideMe($('np_table'));
		unHideMe($('np_prev'));
		unHideMe($('np_start'));
		rdetailPrev = function() { _rdetailNav(prevRecord); };
		rdetailStart = function() { _rdetailNav(cachedRecords.ids[0]); };
	}

	if(nextRecord) {
		unHideMe($('np_table'));
		unHideMe($('np_next'));
		unHideMe($('np_end'));
		rdetailNext = function() { _rdetailNav(nextRecord); };
		rdetailEnd = function() { _rdetailNav(cachedRecords.ids[cachedRecords.ids.length-1]); };
	}

	runEvt('rdetail', 'nextPrevDrawn', i, cachedRecords.ids.length);
}


function _rdetailNav(id) {
	var args = {};
	args[PARAM_RID] = id;
	goTo(buildOPACLink(args));
}

function rdetailDraw() {

	detachAllEvt('common','depthChanged');
	detachAllEvt('common','locationUpdated');
	attachEvt('common','depthChanged', rdetailReload);
	attachEvt('common','locationUpdated', rdetailReload);
	attachEvt('common','holdUpdated', rdetailReload);
	attachEvt('common','holdUpdateCanceled', rdetailReload);

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

	detachAllEvt("result", "idsReceived");
	G.evt.result.hitCountReceived = [];
	G.evt.result.recordReceived = [];
	G.evt.result.copyCountsReceived = [];
	G.evt.result.allRecordsReceived = [];
}

function rdetailGetPageIds() {
	attachEvt("result", "idsReceived", rdetailSetPaging );
	rresultCollectIds();
}

function buildunAPISpan (span, type, id) {
        var cgi = new CGI();
        var d = new Date();

        addCSSClass(span,'unapi-id');

        span.setAttribute(
                'title',
                'tag:' + cgi.server_name + ',' +
                        d.getFullYear() +
                        ':' + type + '/' + id
        );
}

function rdetailViewMarc(r,id) {
	hideMe($('rdetail_extras_loading'));
	$('rdetail_view_marc_box').innerHTML = r.getResultObject();

	var d = new Date();

	var div = elem('div', { "class" : 'hide_me' });
	var span = div.appendChild( elem('abbr') );

	buildunAPISpan( span, 'biblio-record_entry', record.doc_id() );

	$('rdetail_view_marc_box').insertBefore(span, $('rdetail_view_marc_box').firstChild);
}


function rdetailShowLocalCopies() {
	rdetailShowLocal = true;
	rdetailBuildInfoRows();
	hideMe(G.ui.rdetail.cp_info_local);
	unHideMe(G.ui.rdetail.cp_info_all);
	hideMe(G.ui.rdetail.cp_info_none); 
}

function rdetailShowAllCopies() {

	rdetailShowLocal = false;
	rdetailBuildInfoRows();
	hideMe(G.ui.rdetail.cp_info_all);
	unHideMe(G.ui.rdetail.cp_info_local);
	hideMe(G.ui.rdetail.cp_info_none); 
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
	$('rdetail_physical_desc').appendChild(text(record.physical_description()));
	G.ui.rdetail.tor.appendChild(text(record.types_of_resource()[0]));
	setResourcePic( G.ui.rdetail.tor_pic, record.types_of_resource()[0]);
	G.ui.rdetail.abstr.appendChild(text(record.synopsis()));


	// see if the record has any external links 
	var links = record.online_loc();
	for( var i = 0; links && links.length > 0 && i < links.length; i++ ) {
		var href = links[i];
		if( href.match(/http/) ) {
			unHideMe($('rdetail_online_row'));
			var name = links[i+1];
			if(!name || name.match(/http/)) name = href;
			$('rdetail_online').appendChild(elem('a', {href:href,'class':'classic_link'}, name));
			$('rdetail_online').appendChild(elem('br'));
		}
	}



	$('rdetail_place_hold').setAttribute(
		'href','javascript:holdsDrawEditor({record:"'+record.doc_id()+'",type:"T"});');

	G.ui.rdetail.image.setAttribute("src", buildISBNSrc(cleanISBN(record.isbn())));
	runEvt("rdetail", "recordDrawn");
	recordsCache.push(record);

	rdetailSetExtrasSelector();

	var breq = new Request(FETCH_BRE, [getRid()]);
	breq.callback( rdetailCheckDeleted );
	breq.send();

	resultBuildCaches( [ record ] );
	resultDrawSubjects();
	resultDrawSeries();

	// grab added content 
	acCollectData(cleanISBN(record.isbn()), rdetailhandleAC);
}



function rdetailCheckDeleted(r) {
	var br = r.getResultObject()[0];
	if( br.deleted() == 1 ) {
		hideMe($('rdetail_place_hold'));
		$('rdetail_more_actions_selector').disabled = true;
		unHideMe($('rdetail_deleted_exp'));
	}
}

function rdetailSetExtrasSelector() {
	if(!grabUser()) return;
	unHideMe($('rdetail_more_actions'));

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
	doSelectorActions(selector);

	for( var i = 0; i != containers.length; i++ ) {
		found = true;
		var container = containers[i];
		insertSelectorVal( selector, index++, container.name(), 
			"container_" + container.id(), rdetailAddToBookbag,  1 );
	}

	nextContainerIndex = index;
}

var _actions = {};
function rdetailNewBookbag() {
	var name = prompt($('rdetail_bb_new').innerHTML,"");
	if(!name) return;

	var id;
	if( id = containerCreate( name ) ) {
		alert($('rdetail_bb_success').innerHTML);
		var selector = $('rdetail_more_actions_selector');
		insertSelectorVal( selector, nextContainerIndex++, name, 
			"container_" + id, rdetailAddToBookbag, 1 );
		setSelector( selector, 'start' );
	}
}


function rdetailAddToBookbag() {
	var selector = $('rdetail_more_actions_selector');
	var id = selector.options[selector.selectedIndex].value;
	setSelector( selector, 'start' );

	if( containerCreateItem( id.substring(10), record.doc_id() )) {
		alert($('rdetail_bb_item_success').innerHTML);
	}
}


var rdetailMarcFetched = false;
function rdetailShowExtra(type, args) {

	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_anotes_div'));
	hideMe($('rdetail_excerpt_div'));
	hideMe($('rdetail_marc_div'));
	hideMe($('cn_browse'));
	hideMe($('rdetail_cn_browse_div'));
	hideMe($('rdetail_notes_div'));

	removeCSSClass($('rdetail_copy_info_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_viewcn_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_reviews_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_toc_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_excerpt_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_anotes_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_annotation_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_viewmarc_link'), 'rdetail_extras_selected');

	switch(type) {

		case "copyinfo": 
			unHideMe($('rdetail_copy_info_div')); 
			addCSSClass($('rdetail_copy_info_link'), 'rdetail_extras_selected');
			break;

		case "reviews": 
			addCSSClass($('rdetail_reviews_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_reviews_div')); 
			break;


		case "excerpt": 
			addCSSClass($('rdetail_excerpt_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_excerpt_div'));
			break;

		case "anotes": 
			addCSSClass($('rdetail_anotes_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_anotes_div'));
			break;


		case "toc": 
			addCSSClass($('rdetail_toc_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_toc_div'));
			break;

		case "marc": 
			addCSSClass($('rdetail_viewmarc_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_marc_div')); 
			if(rdetailMarcFetched) return;
			unHideMe($('rdetail_extras_loading'));
			rdetailMarcFetched = true;
			var req = new Request( FETCH_MARC_HTML, record.doc_id() );
			req.callback(rdetailViewMarc); 
			req.send();
			break;

		case 'cn':
			addCSSClass($('rdetail_viewcn_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_cn_browse_div'));
			rdetailShowCNBrowse(defaultCN, getLocation(), null, true);
			break;

	}
}

function rdetailVolumeDetails(args) {
	var row = $(args.rowid);
	var tbody = row.parentNode;
	cpdBuild( tbody, row, record, args.cn, args.org, args.depth );
	return;
}


function rdetailBuildCNList() {

	var select = $('cn_browse_selector');
	var index = 0;
	var arr = [];
	for( var cn in callnumberCache ) arr.push( cn );
	arr.sort();

	if( arr.length == 0 ) {
		hideMe($('rdetail_cn_browse_select_div'));
		return;
	}

	for( var i in arr ) {
		var cn = arr[i];
		var opt = new Option(cn);
		select.options[index++] = opt;
	}
	select.onchange = rdetailGatherCN;
}

function rdetailGatherCN() {
	var cn = getSelectorVal($('cn_browse_selector'));
	rdetailShowCNBrowse( cn, getLocation(), getDepth(), true );
	setSelector( $('cn_browse_selector'), cn );
}


function rdetailShowCNBrowse( cn, loc, depth, fromOnclick ) {

	if(!cn) {
		unHideMe($('cn_browse_none'));
		hideMe($('rdetail_cn_browse_select_div'));
		return;
	}
		
	unHideMe($('rdetail_cn_browse_select_div'));
	rdetailBuildCNList();
	setSelector( $('cn_browse_selector'), cn );
	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_marc_div'));
	unHideMe($('rdetail_cn_browse_div'));
	unHideMe($('cn_browse'));
	if( !rdetailLocalOnly && ! fromOnclick ) depth = findOrgDepth(globalOrgTree);
	cnBrowseGo(cn, loc, depth);
}

function rdetailhandleAC(data) {

	if( data.reviews.html ) {
		$('rdetail_review_container').innerHTML = data.reviews.html;
		unHideMe($('rdetail_reviews_link'));
	}

	if( data.toc.html ) {
		$('rdetail_toc_div').innerHTML = data.toc.html;
		unHideMe($('rdetail_toc_link'));
	}

	if( data.excerpt.html ) {
		$('rdetail_excerpt_div').innerHTML = data.excerpt.html;
		unHideMe($('rdetail_excerpt_link'));
	}

	if( data.anotes.html ) {
		$('rdetail_anotes_div').innerHTML = data.anotes.html;
		unHideMe($('rdetail_anotes_link'));
	}
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
	var req;
	if( rdetailShowLocal ) 
		req = new Request(FETCH_COPY_COUNTS_SUMMARY, record.doc_id(), getLocation(), getDepth())
	else
		req = new Request(FETCH_COPY_COUNTS_SUMMARY, record.doc_id());
	req.callback(_rdetailBuildInfoRows);
	req.send();
}

function _rdetailRows(node) {

	if( rdetailShowLocal && getLocation() != globalOrgTree.id() ) {

		var loc = findOrgUnit(getLocation());

		if( !node ) {
			for( var i = 0; i < globalOrgTree.children().length; i++ ) {
				var org = findOrgUnit(globalOrgTree.children()[i]);
				if( orgIsMine(org, loc) ) {
					node = org;
					break;
				}
			}
		} else {
			// if the current node is not in our node trail 
			var trail = orgNodeTrail(loc);
			var intrail = grep( trail, function(i) { return (i.id() == node.id()); } );
			if(!intrail) return;
		}
	}


	if(node) {

		var row = copyRow.cloneNode(true);
		row.id = "cp_info_" + node.id();

		var libtd = findNodeByName( row, config.names.rdetail.lib_cell );
		var cntd  = findNodeByName( row, config.names.rdetail.cn_cell );
		var cpctd = findNodeByName( row, config.names.rdetail.cp_count_cell );
		var actions = $n(row, 'rdetail_actions_cell');
	
		var p = libtd.getElementsByTagName('a')[0];
		libtd.insertBefore(text(node.name()), p);
		libtd.setAttribute("style", "padding-left: " + ((findOrgDepth(node) - 1)  * 9) + "px;");
	
		if(!findOrgType(node.ou_type()).can_have_vols()) {

			row.removeChild(cntd);
			row.removeChild(cpctd);
			row.removeChild(actions);
			row.setAttribute('novols', '1');

			libtd.setAttribute("colspan", numStatuses + 3 );
			libtd.colSpan = numStatuses + 3;
			addCSSClass(row, 'copy_info_region_row');
		} 
	
		copyRowParent.appendChild(row);

	} else { node = globalOrgTree; }

	for( var c in node.children() ) 
		_rdetailRows(node.children()[c]);
}

function rdetailCNPrint(orgid, cn) {
	var div = cpdBuildPrintWindow( record, orgid);
	var template = div.removeChild($n(div, 'cnrow'));
	var rowNode = $("cp_info_" + orgid);
	cpdStylePopupWindow(div);
	openWindow(div.innerHTML);
}

var localCNFound = false;
var ctr = 0;
function _rdetailBuildInfoRows(r) {

	removeChildren(copyRowParent);

	_rdetailRows();

	var summary = r.getResultObject();
	if(!summary) return;

	var found = false;
	for( var i = 0; i < summary.length; i++ ) {

		var arr = summary[i];
		globalCNCache[arr[1]] = 1;
		var thisOrg = findOrgUnit(arr[0]);
		var rowNode = $("cp_info_" + thisOrg.id());
		if(!rowNode) continue;

		if(rowNode.getAttribute("used")) {

			if( rowNode.nextSibling )
				rowNode = copyRowParent.insertBefore(copyRow.cloneNode(true), rowNode.nextSibling);
			else
				rowNode = copyRowParent.appendChild(copyRow.cloneNode(true));
			var n = findNodeByName( rowNode, config.names.rdetail.lib_cell );
			n.appendChild(text(thisOrg.name()));
			n.setAttribute("style", "padding-left: " + ((findOrgDepth(thisOrg) - 1)  * 9) + "px;");
			rowNode.id = "cp_info_" + thisOrg.id() + '_' + (++ctr); //

		} else {
			rowNode.setAttribute("used", "1");
		}

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

		if(isLocal) unHideMe(rowNode);

		rdetailSetPath( thisOrg, isLocal );
		rdetailBuildBrowseInfo( rowNode, arr[1], isLocal, thisOrg );

		if( i == summary.length - 1 && !defaultCN) defaultCN = arr[1];
	}

	if(!found) unHideMe(G.ui.rdetail.cp_info_none);
}


function rdetailBuildBrowseInfo(row, cn, local, orgNode) {

	if(local) {
		var cache = callnumberCache[cn];
		if( cache ) cache.count++;
		else callnumberCache[cn] = { count : 1 };
	}

	var depth = getDepth();
	if( !local ) depth = findOrgDepth(globalOrgTree);

	$n(row, 'rdetail_callnumber_cell').appendChild(text(cn));

	_debug('setting action clicks for cn ' + cn);

	var dHref = 'javascript:rdetailVolumeDetails('+
		'{rowid : "'+row.id+'", cn :"'+cn+'", depth:"'+depth+'", org:"'+orgNode.id()+'", local: '+local+'});';

	var bHref = 'javascript:rdetailShowCNBrowse("' + cn + '", '+orgNode.id()+', "'+depth+'");'; 

	$n(row, 'details').setAttribute('href', dHref);
	$n(row, 'browse').setAttribute('href', bHref);

	if(isXUL()) {
		unHideMe($n(row, 'hold_div'));
		$n(row, 'hold').onclick = function() {
			var req = new Request(FETCH_VOLUME_BY_INFO, cn, record.doc_id(), orgNode.id());
			req.callback(
				function(r) {
					var vol = r.getResultObject();
					holdsDrawEditor({type: 'V', volumeObject : vol});
				}
			);
			req.send();
		};
	}
}


// sets the path to org as 'active' and displays the path if it's local 
function rdetailSetPath(org, local) {
	if( findOrgDepth(org) == 0 ) return;
	var row = $("cp_info_" + org.id());
	row.setAttribute("hasinfo", "1");
	unHideMe(row);
	rdetailSetPath(findOrgUnit(org.parent_ou()), local);
}




//Append all the statuses for a give summary to the 
//copy summary table 
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


var _statusPositions = {};

//Add one td (creating a new column) to the copy summary
//table for each holdable copy status

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


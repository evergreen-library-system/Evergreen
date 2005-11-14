
var recordsHandled = 0;
var recordsCache = [];

/* set up the event handlers */
G.evt.result.hitCountReceived.push(resultSetHitInfo);
G.evt.result.recordReceived.push(resultDisplayRecord, resultAddCopyCounts);
G.evt.result.copyCountsReceived.push(resultDisplayCopyCounts);
G.evt.result.allRecordsReceived.push(resultBuildCaches, resultDrawSubjects, resultDrawAuthors, resultDrawSeries);

/* do this after we have ID's so the rank for mr pages will be correct */
attachEvt("result", "preCollectRecords", resultPaginate);

/* returns the last 'index' postion ocurring in this page */
function resultFinalPageIndex() {
	if(getHitCount() < (getOffset() + getDisplayCount())) 
		return getHitCount() - 1;
	return getOffset() + getDisplayCount() - 1;
}

/* set the search result info, number of hits, which results we're 
	displaying, links to the next/prev pages, etc. */
function resultSetHitInfo() { 
	var c;  
	if( getDisplayCount() > (getHitCount() - getOffset()))  c = getHitCount();
	else c = getDisplayCount() + getOffset();

	var pages = getHitCount() / getDisplayCount();
	if(pages % 1) pages = parseInt(pages) + 1;

	G.ui.result.current_page.appendChild(text( (getOffset()/getDisplayCount()) + 1));
	G.ui.result.num_pages.appendChild(text(pages + ")")); /* the ) is dumb */

	G.ui.result.offset_start.appendChild(text(getOffset() + 1));
	G.ui.result.offset_end.appendChild(text(c));
	G.ui.result.result_count.appendChild(text(getHitCount()));
	unHideMe(G.ui.result.info);
}


function resultPaginate() {
	var o = getOffset();

	if( !((o + getDisplayCount()) >= getHitCount()) ) {

		var args = {};
		args[PARAM_OFFSET] = o + getDisplayCount();
		G.ui.result.next_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.next_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = getHitCount() - (getHitCount() % getDisplayCount());
		G.ui.result.end_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.end_link, config.css.result.nav_active);
	}

	if( o > 0 ) {

		var args = {};
		args[PARAM_OFFSET] = o - getDisplayCount();
		G.ui.result.prev_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.prev_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = 0;
		G.ui.result.home_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.home_link, config.css.result.nav_active);
	}
	if(getDisplayCount() < getHitCount())
		unHideMe($('start_end_links_span'));
}


/* display the record info in the record display table 'pos' is the 
		zero based position the record should have in the display table */
function resultDisplayRecord(rec, pos, is_mr) {

	if(rec == null) rec = new mvr(); /* so the page won't die if there was an error */
	recordsHandled++;
	recordsCache.push(rec);

	var r = table.rows[pos + 1];
	
	try {
		var rank = parseFloat(ranks[pos + getOffset()]);
		rank = ( rank / getTopRank() ) * 100;
		rank = parseInt(rank) + "%";
		var relspan = $n(r, "relevancy_span");
		relspan.appendChild(text(rank));
		unHideMe(relspan.parentNode);
	} catch(e){ }

	var pic = $n(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(cleanISBN(rec.isbn())));

	var title_link = $n(r, config.names.result.item_title);
	var author_link = $n(r, config.names.result.item_author);

	if( is_mr )  {
		var onlyrec = onlyrecord[ getOffset() + pos ];
		if(onlyrec) {
			var args = {};
			args.page = RDETAIL;
			args[PARAM_OFFSET] = 0;
			args[PARAM_RID] = onlyrec;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
			title_link.setAttribute("href", buildOPACLink(args));
			title_link.appendChild(text(normalize(truncate(rec.title(), 65))));
			
		} else {
			buildTitleLink(rec, title_link); 
			var args = {};
			args.page = RRESULT;
			args[PARAM_OFFSET] = 0;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
		}

	} else {
		buildTitleDetailLink(rec, title_link); 
		var args = {};
		args.page = RDETAIL;
		args[PARAM_OFFSET] = 0;
		args[PARAM_RID] = rec.doc_id();
		pic.parentNode.setAttribute("href", buildOPACLink(args));

		unHideMe($n(r,'place_hold_span'));
		$n(r,'place_hold_link').setAttribute(
			'href','javascript:resultDrawHoldsWindow("'+rec.doc_id()+'");');
	}

	buildSearchLink(STYPE_AUTHOR, rec.author(), author_link);

	if(! is_mr ) {
	
		if(!isNull(rec.edition()))	{
			unHideMe( $n(r, "result_table_extra_span"));
			$n(r, "result_table_edition_span").appendChild( text( rec.edition()) );
		}
		if(!isNull(rec.pubdate())) {
			unHideMe( $n(r, "result_table_extra_span"));
			unHideMe($n(r, "result_table_pub_span"));
			$n(r, "result_table_pub_span").appendChild( text( rec.pubdate() ));
		}
		if(!isNull(rec.publisher()) ) {
			unHideMe( $n(r, "result_table_extra_span"));
			unHideMe($n(r, "result_table_pub_span"));
			$n(r, "result_table_pub_span").appendChild( text( " " + rec.publisher() ));
		}
	}

	resultBuildFormatIcons( r, rec );

	unHideMe(r);
	
	runEvt("result", "recordDrawn", rec.doc_id(), title_link);

	if(resultPageIsDone())  {
		/* hide the 'now loading...' message */
		/*
		hideMe(G.ui.common.loading);
		*/
		runEvt('result', 'allRecordsReceived', recordsCache);
	}
}

function _resultFindRec(id) {
	for( var i = 0; i != recordsCache.length; i++ ) {
		var rec = recordsCache[i];
		if( rec && rec.doc_id() == id )
			return rec;
	}
	return null;
}

var currentHoldRecord;
var holdsOrgSelectorBuilt = false;
function resultDrawHoldsWindow(recid) {

	if(recid == null) {
		recid = currentHoldRecord;
		if(recid == null) return;
	}
	currentHoldRecord = recid;

	if(!(G.user && G.user.session)) {

		attachEvt('common','loggedIn', resultDrawHoldsWindow)
		initLogin();
		return;
	}
	swapCanvas($('holds_box'));

	var rec = _resultFindRec(recid);

	if(!holdsOrgSelectorBuilt) {
		resultBuildHoldsSelector(null, 0);
		holdsOrgSelectorBuilt = true;
	}

	removeChildren($('holds_title'));
	removeChildren($('holds_author'));
	removeChildren($('holds_format'));
	removeChildren($('holds_email'));
	removeChildren($('holds_email'));

	$('holds_title').appendChild(text(rec.title()));
	$('holds_author').appendChild(text(rec.author()));

	for( var i in rec.types_of_resource() ) {
		var res = rec.types_of_resource()[i];
		var img = elem("img");
		setResourcePic(img, res);
		$('holds_format').appendChild(text(' '+res+' '));
		$('holds_format').appendChild(img);
		$('holds_format').appendChild(text(' '));
	}

	$('holds_phone').appendChild(text(G.user.day_phone()));
	$('holds_email').appendChild(text(G.user.email()));
	$('holds_cancel').onclick = showCanvas;
	$('holds_submit').onclick = resultPlaceHold; 
}


function resultBuildHoldsSelector(node, depth) {

	if(!node) {
		node = globalOrgTree;
		depth = 0;
	}

	var selector = $('holds_org_selector');
	var index = selector.options.length;

	if(IE) {
		var pre = elem("pre");
		for(var x=2; x <= findOrgType(node.ou_type()).depth(); x++) {
			pre.appendChild(text("    "));
		}
		pre.appendChild(text(node.name()));
		var select = new Option("", node.id());
		selector.options[index] = select;
		select.appendChild(pre);
	
	} else {
		var pad = (findOrgType(node.ou_type()).depth() - 1) * 12;
		var select = new Option(node.name(), node.id());
		select.setAttribute("style", "padding-left: " + pad);
		selector.options[index] = select;
	}	

	if( node.id() == getLocation() ) {
		selector.selectedIndex = index;
		selector.options[index].selected = true;	
	}

	for( var i in node.children() ) {
		var child = node.children()[i];
		if(child) {
			resultBuildHoldsSelector(child, depth+1);
		}
	}
}

function resultPlaceHold() {
	//alert("placing hold for " + currentHoldRecord );

	var hold = new ahr();
	hold.pickup_lib( 1 ); /* */
	hold.requestor(G.user.id());
	hold.usr(G.user.id());
	hold.hold_type('T');
	hold.email_notify(G.user.email());
	hold.phone_notify(G.user.day_phone());
	hold.target(currentHoldRecord);
	
	var req = new Request( CREATE_HOLD, G.user.session, hold );
	req.send(true);
	var res = req.result();

	/* XMLize me */
	if( res == '1' ) {
		alert('ok');
	} else {
		alert('hold failed');
	}
}



function resultBuildFormatIcons( row, rec ) {

	var ress = rec.types_of_resource();

	for( var i in ress ) {

		var res = ress[i];
		var link = $n(row, res + "_link");
		link.title = res;
		var img = link.getElementsByTagName("img")[0];
		removeCSSClass( img, config.css.dim );

		var f = getForm();
		if( f != "all" ) {
			/*
			if( f != modsFormatToMARC(res) ) 
				addCSSClass( img, config.css.dim2);
			else
				addCSSClass( img, "dim2_border");
				*/
			if( f == modsFormatToMARC(res) ) 
				addCSSClass( img, "dim2_border");
		}


		var args = {};
		args.page = RRESULT;
		args[PARAM_OFFSET] = 0;
		args[PARAM_MRID] = rec.doc_id();
		args[PARAM_FORM] = modsFormatToMARC(res);

		link.setAttribute("href", buildOPACLink(args));

	}

}


function resultPageIsDone(pos) {
	return (recordsHandled == getDisplayCount() 
		|| recordsHandled + getOffset() == getHitCount());
}

var resultCCHeaderApplied = false;

/* -------------------------------------------------------------------- */
/* dynamically add the copy count rows based on the org type 'countsrow' 
	is the row into which we will add TD's to hold the copy counts 
	This code generates copy count cells with an id of
	'copy_count_cell_<depth>_<pagePosition>'  */
function resultAddCopyCounts(rec, pagePosition) {

	var r = table.rows[pagePosition + 1];
	var countsrow = $n(r, config.names.result.counts_row );
	var ccell = $n(countsrow, config.names.result.count_cell);

	var nodes = orgNodeTrail(findOrgUnit(getLocation()));
	var node = nodes[0];
	var type = findOrgType(node.ou_type());
	ccell.id = "copy_count_cell_" + type.depth() + "_" + pagePosition;
	ccell.title = type.opac_label();
	//addCSSClass(ccell, config.css.result.cc_cell_even);

	var lastcell = ccell;
	var lastheadcell = null;

	var cchead = null;
	var ccheadcell = null;
	if(!resultCCHeaderApplied) {
		ccrow = $('result_thead_row');
		ccheadcell =  ccrow.removeChild($n(ccrow, "result_thead_ccell"));
		var t = ccheadcell.cloneNode(true);
		lastheadcell = t;
		t.appendChild(text(type.opac_label()));
		ccrow.appendChild(t);
		resultCCHeaderApplied = true;
	}

	if(nodes[1]) {

		var x = 1;
		var d = findOrgDepth(nodes[1]);
		var d2 = findOrgDepth(nodes[nodes.length -1]);

		for( var i = d; i <= d2 ; i++ ) {
	
			ccell = ccell.cloneNode(true);

			//if((i % 2)) removeCSSClass(ccell, "copy_count_cell_even");
			//else addCSSClass(ccell, "copy_count_cell_even");

			var node = nodes[x++];
			var type = findOrgType(node.ou_type());
	
			ccell.id = "copy_count_cell_" + type.depth() + "_" + pagePosition;
			ccell.title = type.opac_label();
			countsrow.insertBefore(ccell, lastcell);
			lastcell = ccell;

			if(ccheadcell) {
				var t = ccheadcell.cloneNode(true);
				t.appendChild(text(type.opac_label()));
				ccrow.insertBefore(t, lastheadcell);
				lastheadcell = t;
			}
		}
	}

	unHideMe($("search_info_table"));
}

/* collect copy counts for a record using method 'methodName' */
function resultCollectCopyCounts(rec, pagePosition, methodName) {
	if(rec == null || rec.doc_id() == null) return;
	var req = new Request(methodName, getLocation(), rec.doc_id(), getForm() );
	req.request.userdata = [ rec, pagePosition ];
	req.callback(resultHandleCopyCounts);
	req.send();
}

function resultHandleCopyCounts(r) {
	runEvt('result', 'copyCountsReceived', r.userdata[0], r.userdata[1], r.getResultObject()); 
}


/* display the collected copy counts */
function resultDisplayCopyCounts(rec, pagePosition, copy_counts) {
	if(copy_counts == null || rec == null) return;
	var i = 0;
	while(copy_counts[i] != null) {
		var cell = $("copy_count_cell_" + i +"_" + pagePosition);
		/*
		var span = cell.getElementsByTagName("div")[0];
		*/
		cell.appendChild(text(copy_counts[i].available + " / " + copy_counts[i].count));

		i++;
	}
}


/* captures extraneous info from each record */

var subjectCache = {};
var authorCache = {};
var seriesCache = {};

function resultBuildCaches(records) {
	for( var r in records ) {
		var rec = records[r];
		for( var s in rec.subject() ) 
			subjectCache[s] == null ? subjectCache[s] = 1 : subjectCache[s]++;
		authorCache[rec.author()] = 1;
		for( var s in rec.series() ) seriesCache[rec.series()[s]] = 1;
	}
}

function resultSortSubjects(a, b) { return -(a.count - b.count); } /* sort in reverse */
function resultDrawSubjects() {

	var subjs = [];
	for( var s in subjectCache )
		subjs.push( { sub : s, count : subjectCache[s] } );
	subjs.sort(resultSortSubjects);

	var ss = [];
	for( var s in subjs ) ss.push(subjs[s].sub);

	resultDrawSidebarTrees( 
		STYPE_SUBJECT, 
		"subjectSidebarTree", ss, 
		$("subject_tree_sidebar"), 
		$("subject_sidebar_tree_div") );
}

function resultDrawAuthors() {
	var auths = new Array();
	for( var s in authorCache ) auths.push(s);

	resultDrawSidebarTrees( 
		STYPE_AUTHOR, 
		"authorSidebarTree", auths.sort(), 
		$("author_tree_sidebar"), 
		$("author_sidebar_tree_div") );
}

function resultDrawSeries() {
	var sers = new Array();
	for( var s in seriesCache ) sers.push(s);
	resultDrawSidebarTrees( 
		STYPE_SERIES, 
		"seriesSidebarTree", sers.sort(), 
		$("series_tree_sidebar"), 
		$("series_sidebar_tree_div") );
}

function resultDrawSidebarTrees( stype, treeName, items, wrapperNode, destNode ) {
	var tree;
	eval("tree = " + treeName);

	var found = false;
	var x = 0;
	for( var i in items ) {

		if(isNull(items[i])) continue;
		if(x++ > 7) break;
		found = true;

		var item = normalize(truncate(items[i], 65));
		var trunc = 65;
		var args = {};
		var href = resultQuickLink( items[i], stype );
		tree.addNode( stype + "_" + items[i], treeName + 'Root', item, href );

		/*
		if(!IE)
			setTimeout('resultFireXRefReq("'+treeName+'","'+stype+'","'+item+'");',200);
			*/
		if(!IE) resultFireXRefReq(treeName, stype, items[i]);
	}

	if(found) {
		unHideMe(wrapperNode);
		//tree.close(tree.rootid);
	}
}

function resultFireXRefReq( treeName, stype, item ) {
	var tree;
	eval('tree=' + treeName);
	var req = new Request(FETCH_CROSSREF, stype, item);
	req.request._tree = tree;
	req.request._item = item;
	req.request._stype = stype;
	req.callback(resultAppendCrossRef);
	req.send();
}


function resultQuickLink( term, type ) {
	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = term;
	args[PARAM_STYPE] = type;
	return buildOPACLink(args);
}


function resultAppendCrossRef(r) {
	var tree		= r._tree
	var item		= r._item
	var stype	= r._stype;
	var result	= r.getResultObject();
	if(!result) return;
	var froms	= result['from'];
	var alsos	= result['also'];

	var total = 0;

	for( var i = 0; (total++ < 5 && i < froms.length); i++ ) {
		var string = normalize(truncate(froms[i], 45));
		if($(stype + '_' + froms[i])) continue;
		tree.addNode(stype + '_' + froms[i], 
			stype + '_' + item, string, resultQuickLink(froms[i],stype));
	}
	for( var i = 0; (total++ < 10 && i < alsos.length); i++ ) {
		var string = normalize(truncate(alsos[i], 45));
		if($(stype + '_' + alsos[i])) continue;
		tree.addNode(stype + '_' + alsos[i], 
			stype + '_' + item, string, resultQuickLink(alsos[i],stype));
	}
}






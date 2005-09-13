
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
}


/* display the record info in the record display table 'pos' is the 
		zero based position the record should have in the display table */
function resultDisplayRecord(rec, pos, is_mr) {

	if(rec == null) rec = new mvr(); /* so the page won't die if there was an error */
	recordsHandled++;
	recordsCache.push(rec);

	/* hide the 'now loading...' message */
	hideMe(G.ui.common.loading);

	var r = table.rows[pos + 1];
	
	try {
		var rank = parseFloat(ranks[pos + getOffset()]);
		rank = ( rank / getTopRank() ) * 100;
		rank = parseInt(rank) + "%";
		var relspan = findNodeByName(r, "relevancy_span");
		relspan.appendChild(text(rank));
		unHideMe(relspan.parentNode);
	} catch(e){ }

	var pic = findNodeByName(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(cleanISBN(rec.isbn())));

	var title_link = findNodeByName(r, config.names.result.item_title);
	var author_link = findNodeByName(r, config.names.result.item_author);

	if( is_mr )  {
		var onlyrec = onlyrecord[ getOffset() + pos ];
		if(onlyrec) {
			var id = rec.doc_id();
			rec.doc_id(onlyrec);
			buildTitleDetailLink(rec, title_link); 
			rec.doc_id(id);
		} else buildTitleLink(rec, title_link); 
	} else  buildTitleDetailLink(rec, title_link); 

	buildSearchLink(STYPE_AUTHOR, rec.author(), author_link);

	resultBuildFormatIcons( r, rec );

	unHideMe(r);
	
	runEvt("result", "recordDrawn", rec.doc_id(), title_link);

	if(resultPageIsDone()) 
		runEvt('result', 'allRecordsReceived', recordsCache);
}

function resultBuildFormatIcons( row, rec ) {

	var ress = rec.types_of_resource();

	for( var i in ress ) {

		var res = ress[i];
		var link = findNodeByName(row, res + "_link");
		link.title = res;
		var img = link.getElementsByTagName("img")[0];
		removeCSSClass( img, config.css.dim );

		var f = getForm();
		if( f != "all" ) {
			if( f != modsFormatToMARC(res) ) 
				addCSSClass( img, config.css.dim2);
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
	var countsrow = findNodeByName(r, config.names.result.counts_row );
	var ccell = findNodeByName(countsrow, config.names.result.count_cell);

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
		ccrow = getId('result_thead_row');
		ccheadcell =  ccrow.removeChild(findNodeByName(ccrow, "result_thead_ccell"));
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

	unHideMe(getId("search_info_table"));
}

/* collect copy counts for a record using method 'methodName' */
function resultCollectCopyCounts(rec, pagePosition, methodName) {
	if(rec == null || rec.doc_id() == null) return;
	var req = new Request(methodName, getLocation(), rec.doc_id() );
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
		var cell = getId("copy_count_cell_" + i +"_" + pagePosition);
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
	resultDrawSidebarStuff(STYPE_SUBJECT, G.ui.sidebar.subject_item,  
		config.names.sidebar.subject_item, ss, G.ui.sidebar.subject);
}

function resultDrawAuthors() {
	var auths = new Array();
	for( var s in authorCache ) auths.push(s);
	resultDrawSidebarStuff(STYPE_AUTHOR, G.ui.sidebar.author_item,  
		config.names.sidebar.author_item, auths.sort(), G.ui.sidebar.author);
}

function resultDrawSeries() {
	var sers = new Array();
	for( var s in seriesCache ) sers.push(s);
	resultDrawSidebarStuff(STYPE_SERIES, G.ui.sidebar.series_item,  
		config.names.sidebar.series_item, sers.sort(), G.ui.sidebar.series);
}

/* search type, template node, href link name, array of text, node to unhide */
function resultDrawSidebarStuff(stype, node, linkname, items, wrapperNode) {
	var parent = node.parentNode;
	var template = parent.removeChild(node);
	var x = 0;
	var newnode = template.cloneNode(true);
	var found = false;
	for( var i in items ) {
		if(isNull(items[i])) continue;
		if(x++ > 7) break;
		buildSearchLink(stype, items[i], findNodeByName(newnode, linkname), 100);
		parent.appendChild(newnode);
		newnode = template.cloneNode(true);
		found = true;
	}
	if(found) unHideMe(wrapperNode);
}






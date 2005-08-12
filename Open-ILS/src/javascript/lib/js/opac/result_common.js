var subjectCache = {};
var authorCache = {};
var seriesCache = {};
var recordsHandled = 0;

function resultFinalPageIndex() {
	if(getHitCount() < (getOffset() + getDisplayCount())) 
		return getHitCount() - 1;
	return getOffset() + getDisplayCount() - 1;
}

/* set the search result info, number of hits, which results we're 
	displaying, links to the next/prev pages, etc. */
function resultSetInfo() { 
	var c;  
	if( getDisplayCount() > (getHitCount() - getOffset()))  c = getHitCount();
	else c = getDisplayCount() + getOffset();

	var pages = getHitCount() / getDisplayCount();
	if(pages % 1) pages = parseInt(pages) + 1;

	G.ui.result.current_page.appendChild(text( (getOffset()/getDisplayCount()) + 1));
	G.ui.result.num_pages.appendChild(text(pages + ")"));

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

	G.ui.result.offset_start.appendChild(text(o + 1));
	G.ui.result.offset_end.appendChild(text(c));
	G.ui.result.result_count.appendChild(text(getHitCount()));
	unHideMe(G.ui.result.info);

}


/* display the record info in the record display table 
	'pos' is the zero based position the record should have in the
	display table */
function resultDisplayRecord(rec, rowtemplate, pos, is_mr) {

	if(rec == null) rec = new mvr(); /* so the page won't die */
	recordsHandled++;

	/* hide the 'now loading...' message */
	hideMe(G.ui.common.loading);

	var r = table.rows[pos];

	var pic = findNodeByName(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(cleanISBN(rec.isbn())));

	var title_link = findNodeByName(r, config.names.result.item_title);
	var author_link = findNodeByName(r, config.names.result.item_author);

	if( is_mr )  buildTitleLink(rec, title_link); 
	else  buildTitleDetailLink(rec, title_link); 
	buildSearchLink(STYPE_AUTHOR, rec.author(), author_link);

	/* grab subjects, authors, and series from the record */
	for( var s in rec.subject() ) 
		subjectCache[s] == null ? subjectCache[s] = 1 : subjectCache[s]++;
	authorCache[rec.author()] = 1;
	for( var s in rec.series() ) seriesCache[rec.series()[s]] = 1;

	if(resultPageIsDone() && !subjectsAreDrawn) {
		subjectsAreDrawn = true;
		resultDrawSubjects();
		resultDrawAuthors();
		resultDrawSeries();
	}


	var countsrow = findNodeByName(r, config.names.result.counts_row);

	/* adjust the width according to how many org counts are added */
	findNodeByName(r, "result_table_title_cell").width = 
		resultAddCopyCounts(countsrow, rec) + "%";

	unHideMe(r);

}

var subjectsAreDrawn = false;
function resultPageIsDone(pos) {
	return (recordsHandled == getDisplayCount() 
		|| recordsHandled + getOffset() == getHitCount());
}


/* -------------------------------------------------------------------- */
/* dynamically add the copy count rows based on the org type 
	'countsrow' is the row into which we will add TD's to hold
	the copy counts 
	This code generates copy count cells with an id of
	'copy_count_cell_<depth>_<record_id>' for later insertion of copy counts
	return the percent width left over after the each count is added. 
	if 3 counts are added, returns 100 - (cell.width * 3) */
function resultAddCopyCounts(countsrow, rec) {

	var ccell = findNodeByName(countsrow, config.names.result.count_cell);


	var nodes = orgNodeTrail(findOrgUnit(getLocation()));
	var node = nodes[0];
	var type = findOrgType(node.ou_type());
	ccell.id = "copy_count_cell_" + type.depth() + "_" + rec.doc_id();
	ccell.title = type.opac_label();
	addCSSClass(ccell, "copy_count_cell_even");

	var lastcell = ccell;

	if(nodes[1]) {

		var x = 1;
		var d = findOrgDepth(nodes[1]);
		var d2 = findOrgDepth(nodes[nodes.length -1]);

		for( var i = d; i <= d2 ; i++ ) {
	
			ccell = ccell.cloneNode(true);

			if((i % 2))
				removeCSSClass(ccell, "copy_count_cell_even");
			else
				addCSSClass(ccell, "copy_count_cell_even");

			var node = nodes[x++];
			var type = findOrgType(node.ou_type());
	
			ccell.id = "copy_count_cell_" + type.depth() + "_" + rec.doc_id();
			ccell.title = type.opac_label();
			countsrow.insertBefore(ccell, lastcell);
			lastcell = ccell;
		}
	}

	return 100 - (nodes.length * 8);

}

/* collect copy counts for a record using method 'methodName' */
function resultCollectCopyCounts(rec, methodName) {
	if(rec == null || rec.doc_id() == null) return;
	var req = new Request(methodName, getLocation(), rec.doc_id() );
	req.request.userdata = rec;
	req.callback(resultHandleCopyCounts);
	req.send();
}

function resultHandleCopyCounts(r) {
	resultDisplayCopyCounts(r.userdata, r.getResultObject()); 
}


/* display the collected copy counts */
function resultDisplayCopyCounts(rec, copy_counts) {
	if(copy_counts == null || rec == null) return;
	var i = 0;
	while(copy_counts[i] != null) {
		var cell = getId("copy_count_cell_" + i +"_" + rec.doc_id());
		cell.appendChild(text(copy_counts[i].available + " / " + copy_counts[i].count));
		i++;
	}
}

function resultSortSubjects(a, b) { return -(a.count - b.count); } /* sort in reverse */

function resultDrawSubjects() {

	var subjs = [];
	for( var s in subjectCache )
		subjs.push( { sub : s, count : subjectCache[s] } );
	subjs.sort(resultSortSubjects);

	var template = G.ui.sidebar.subject.removeChild(G.ui.sidebar.subject_item);
	var x = 0;
	var newnode = template.cloneNode(true);

	var found = false;
	for( var s in subjs ) {
		if(isNull(subjs[s])) continue;
		if(x++ > 7) break;
		buildSearchLink(STYPE_SUBJECT, subjs[s].sub, 
			findNodeByName(newnode, config.names.sidebar.subject_item), 30);
		G.ui.sidebar.subject.appendChild(newnode);
		newnode = template.cloneNode(true);
		found = true;
	}
	if(found) unHideMe(G.ui.sidebar.subject);
}

function resultDrawAuthors() {

	var template = G.ui.sidebar.author.removeChild(G.ui.sidebar.author_item);
	var x = 0;
	var newnode = template.cloneNode(true);

	var auths = new Array();
	for( var s in authorCache ) auths.push(s);
	auths = auths.sort();

	var found = false;
	for( var i in auths ) {
		if(isNull(auths[i])) continue;
		if(x++ > 7) break;
		buildSearchLink(STYPE_AUTHOR, auths[i], findNodeByName(newnode, config.names.sidebar.author_item), 30);
		G.ui.sidebar.author.appendChild(newnode);
		newnode = template.cloneNode(true);
		found = true;
	}
	if(found) unHideMe(G.ui.sidebar.author);
}


function resultDrawSeries() {
	var template = G.ui.sidebar.series.removeChild(G.ui.sidebar.series_item);
	var x = 0;
	var newnode = template.cloneNode(true);

	var sers = new Array();
	for( var s in seriesCache ) sers.push(s);
	sers = sers.sort();

	var found = false;
	for( var i in sers ) {
		if(isNull(sers[i])) continue;
		if(x++ > 7) break;
		buildSearchLink(STYPE_SERIES, sers[i], findNodeByName(newnode, config.names.sidebar.series_item), 30);
		G.ui.sidebar.series.appendChild(newnode);
		newnode = template.cloneNode(true);
		found = true;
	}
	if(found) unHideMe(G.ui.sidebar.series);

}






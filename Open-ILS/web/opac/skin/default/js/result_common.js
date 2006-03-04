
var recordsHandled = 0;
var recordsCache = [];
var lowHitCount = 4;

/* set up the event handlers */
G.evt.result.hitCountReceived.push(resultSetHitInfo);
G.evt.result.recordReceived.push(resultDisplayRecord, resultAddCopyCounts);
G.evt.result.copyCountsReceived.push(resultDisplayCopyCounts);
G.evt.result.allRecordsReceived.push(resultBuildCaches, resultDrawSubjects, resultDrawAuthors, resultDrawSeries);
//G.evt.result.allRecordsReceived.push(resultBuildCaches );

attachEvt('result','lowHits',resultLowHits);
attachEvt('result','zeroHits',resultZeroHits);

attachEvt( "common", "locationUpdated", resultSBSubmit );
function resultSBSubmit(){searchBarSubmit();}

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

	try{searchTimer.stop()}catch(e){}

	if( findCurrentPage() == MRESULT ) {
		if(getHitCount() <= lowHitCount && getTerm())
			runEvt('result', 'lowHits');
		if(getHitCount() == 0) {
			runEvt('result', 'zeroHits');
			return;
		}
	}

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

function resultLowHits() {
	showCanvas();
	unHideMe($('result_low_hits'));
	if(getHitCount() > 0)
		unHideMe($('result_low_hits_msg'));

	var sreq = new Request(CHECK_SPELL, getTerm());
	sreq.callback(resultSuggestSpelling);
	sreq.send();

	var words = getTerm().split(' ');
	var word;
	while( word = words.shift() ) {
		var areq = new Request(FETCH_CROSSREF, getStype(), getTerm() );
		areq.callback(resultLowHitXRef);
		areq.send();
	}

	if( !(getForm() == null || getForm() == 'all' || getForm == "") ) {
		var a = {};
		a[PARAM_FORM] = "all";
		$('low_hits_remove_format_link').setAttribute('href',buildOPACLink(a));
		unHideMe($('low_hits_remove_format'));
	}

	resultSuggestSearchClass();
}

var lowHitsXRefLink;
var lowHitsXRefLinkParent;
function resultLowHitXRef(r) {
	if(!lowHitsXRefLink){
		lowHitsXRefLinkParent = $('low_hits_xref_link').parentNode;
		lowHitsXRefLink = lowHitsXRefLinkParent.removeChild($('low_hits_xref_link'));
	}
	var res = r.getResultObject();
	var arr = res.from;
	arr.concat(res.also);
	if(arr && arr.length > 0) {
		unHideMe($('low_hits_cross_ref'));
		var word;
		var c = 0;
		while( word = arr.shift() ) {
			if(c++ > 20) break;
			var a = {};
			a[PARAM_TERM] = word;
			var template = lowHitsXRefLink.cloneNode(true);
			template.setAttribute('href',buildOPACLink(a));
			template.appendChild(text(word));
			lowHitsXRefLinkParent.appendChild(template);
			lowHitsXRefLinkParent.appendChild(text(' '));
		}
	}
}

function resultZeroHits() {
	showCanvas();
	unHideMe($('result_low_hits'));
	unHideMe($('result_zero_hits_msg'));
	if(getTerm()) resultExpandSearch(); /* advanced search */
}

function resultExpandSearch() {
	var top = findOrgDepth(globalOrgTree);
	if(getDepth() == top) return;
	unHideMe($('low_hits_expand_range'));
	var par = $('low_hits_expand_link').parentNode;
	var template = par.removeChild($('low_hits_expand_link'));

	var bottom = getDepth();
	while( top < bottom ) {
		var a = {};
		a[PARAM_DEPTH] = top;
		var temp = template.cloneNode(true);
		temp.appendChild(text(findOrgTypeFromDepth(top).opac_label()))
		temp.setAttribute('href',buildOPACLink(a));
		par.appendChild(temp);
		top++;
	}
}

function resultSuggestSearchClass() {
	var stype = getStype();
	if(stype == STYPE_KEYWORD) return;
	var a = {}; var ref;
	unHideMe($('low_hits_search_type'));
	if(stype != STYPE_TITLE) {
		ref = $('low_hits_title_search');
		unHideMe(ref);
		a[PARAM_STYPE] = STYPE_TITLE;
		ref.setAttribute('href',buildOPACLink(a));
	}
	if(stype != STYPE_AUTHOR) {
		ref = $('low_hits_author_search');
		unHideMe(ref);
		a[PARAM_STYPE] = STYPE_AUTHOR;
		ref.setAttribute('href',buildOPACLink(a));
	}
	if(stype != STYPE_SUBJECT) {
		ref = $('low_hits_subject_search');
		unHideMe(ref);
		a[PARAM_STYPE] = STYPE_SUBJECT;
		ref.setAttribute('href',buildOPACLink(a));
	}
	if(stype != STYPE_KEYWORD) {
		ref = $('low_hits_keyword_search');
		unHideMe(ref);
		a[PARAM_STYPE] = STYPE_KEYWORD;
		ref.setAttribute('href',buildOPACLink(a));
	}
	if(stype != STYPE_SERIES) {
		ref = $('low_hits_series_search');
		unHideMe(ref);
		a[PARAM_STYPE] = STYPE_SERIES;
		ref.setAttribute('href',buildOPACLink(a));
	}
}

function resultSuggestSpelling(r) {
	var res = r.getResultObject();
	if(res) {
		unHideMe($('did_you_mean'));
		var arg = {};
		arg[PARAM_TERM] = res;
		$('spell_check_link').setAttribute(
			'href', buildOPACLink(arg) );
		$('spell_check_link').appendChild(text(res));
	}
}


function resultPaginate() {
	var o = getOffset();

	if( !((o + getDisplayCount()) >= getHitCount()) ) {

		var args = {};
		args[PARAM_OFFSET]	= o + getDisplayCount();
		args[PARAM_SORT]		= SORT;
		args[PARAM_SORT_DIR] = SORT_DIR;
		args[PARAM_RLIST]		= new CGI().param(PARAM_RLIST);

		G.ui.result.next_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.next_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = getHitCount() - (getHitCount() % getDisplayCount());
		G.ui.result.end_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.end_link, config.css.result.nav_active);
	}

	if( o > 0 ) {

		var args = {};
		args[PARAM_SORT]		= SORT;
		args[PARAM_SORT_DIR] = SORT_DIR;
		args[PARAM_RLIST]		= new CGI().param(PARAM_RLIST);

		args[PARAM_OFFSET] = o - getDisplayCount();
		G.ui.result.prev_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.prev_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = 0;
		G.ui.result.home_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.home_link, config.css.result.nav_active);
	}
	if(getDisplayCount() < getHitCount())
		unHideMe($('start_end_links_span'));

	showCanvas();
	try{searchTimer.stop()}catch(e){}
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
		rank		= parseInt( rank * 100 );
		var relspan = $n(r, "relevancy_span");
		relspan.appendChild(text(rank));
		unHideMe(relspan.parentNode);
	} catch(e){ }

	var pic = $n(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(cleanISBN(rec.isbn())));

	var title_link = $n(r, config.names.result.item_title);
	var author_link = $n(r, config.names.result.item_author);

	var d = new Date();

	if( is_mr )  {
		var onlyrec = onlyrecord[ getOffset() + pos ];
		if(onlyrec) {
			var unapi_span = $n(r,'unapi');
			unapi_span.appendChild(
				text(
					normalize( rec.title() ) +
						' (tag:open-ils.org,' +
						d.getFullYear() + '-' +
						(1 + d.getMonth()) + '-' + 
						d.getDate() + 
						':biblio-record_entry/' + onlyrec + ')'
				)
			);
			unapi_span.setAttribute(
				'title',
				'tag:open-ils.org,' +
					d.getFullYear() + '-' +
					(1 + d.getMonth()) + '-' + 
					d.getDate() + 
					':biblio-record_entry/' + onlyrec
			);

			var args = {};
			args.page = RDETAIL;
			args[PARAM_OFFSET] = 0;
			args[PARAM_RID] = onlyrec;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
			title_link.setAttribute("href", buildOPACLink(args));
			title_link.appendChild(text(normalize(truncate(rec.title(), 65))));
			
		} else {
			var unapi_span = $n(r,'unapi');
			unapi_span.appendChild(
				text(
					normalize( rec.title() ) +
						' (tag:open-ils.org,' +
						d.getFullYear() + '-' +
						(1 + d.getMonth()) + '-' + 
						d.getDate() + 
						':metabib-metarecord/' + rec.doc_id() + ')'
				)
			);
			unapi_span.setAttribute(
				'title'
				'tag:open-ils.org,' +
					d.getFullYear() + '-' +
					(1 + d.getMonth()) + '-' + 
					d.getDate() + 
					':biblio-record_entry/' + rec.doc_id()
			);

			buildTitleLink(rec, title_link); 
			var args = {};
			args.page = RRESULT;
			args[PARAM_OFFSET] = 0;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
		}

	} else {
		var unapi_span = $n(r,'unapi');
		unapi_span.appendChild(
			text(
				normalize( rec.title() ) +
					' (tag:open-ils.org,' +
					d.getFullYear() + '-' +
					(1 + d.getMonth()) + '-' + 
					d.getDate() + 
					':biblio-record_entry/' + rec.doc_id() + ')'
			)
		);
		unapi_span.setAttribute(
			'title',
			'tag:open-ils.org,' +
				d.getFullYear() + '-' +
				(1 + d.getMonth()) + '-' + 
				d.getDate() + 
				':biblio-record_entry/' + rec.doc_id()
		);

		buildTitleDetailLink(rec, title_link); 
		var args = {};
		args.page = RDETAIL;
		args[PARAM_OFFSET] = 0;
		args[PARAM_RID] = rec.doc_id();
		pic.parentNode.setAttribute("href", buildOPACLink(args));

		unHideMe($n(r,'place_hold_span'));
		$n(r,'place_hold_link').setAttribute(
			'href','javascript:holdsDrawWindow("'+rec.doc_id()+'");');
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

	resultBuildFormatIcons( r, rec, is_mr );

	unHideMe(r);
	
	runEvt("result", "recordDrawn", rec.doc_id(), title_link);

	/*
	if(resultPageIsDone())  {
		runEvt('result', 'allRecordsReceived', recordsCache);
	}
	*/
}

function _resultFindRec(id) {
	for( var i = 0; i != recordsCache.length; i++ ) {
		var rec = recordsCache[i];
		if( rec && rec.doc_id() == id )
			return rec;
	}
	return null;
}


function resultBuildFormatIcons( row, rec, is_mr ) {

	var ress = rec.types_of_resource();

	for( var i in ress ) {

		var res = ress[i];
		var link = $n(row, res + "_link");
		link.title = res;
		var img = link.getElementsByTagName("img")[0];
		removeCSSClass( img, config.css.dim );

		var f = getForm();
		if( f != "all" ) {
			if( f == modsFormatToMARC(res) ) 
				addCSSClass( img, "dim2_border");
		}

		var args = {};
		args[PARAM_OFFSET] = 0;
		args[PARAM_FORM] = modsFormatToMARC(res);

		if(is_mr) {
			args.page = RRESULT;
			args[PARAM_MRID] = rec.doc_id();
		} else {
			args.page = RDETAIL
			args[PARAM_RID] = rec.doc_id();
		}

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



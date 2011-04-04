dojo.require('openils.BibTemplate');
dojo.requireLocalization("openils.opac", "opac");
var opac_strings = dojo.i18n.getLocalization("openils.opac", "opac");

var recordsHandled = 0;
var recordsCache = [];
var lowHitCount = 4;
var isbnList = '';
var googleBooksLink = true;

var resultFetchAllRecords = false;
var resultCompiledSearch = null;

/* set up the event handlers */
if( findCurrentPage() == MRESULT || findCurrentPage() == RRESULT ) {
	G.evt.result.hitCountReceived.push(resultSetHitInfo);
	G.evt.result.recordReceived.push(resultDisplayRecord, resultAddCopyCounts);
	G.evt.result.copyCountsReceived.push(resultDisplayCopyCounts);
	G.evt.result.allRecordsReceived.push( function(){unHideMe($('result_info_2'))}, fetchGoogleBooksLink, fetchChiliFreshReviews);

	attachEvt('result','lowHits',resultLowHits);
	attachEvt('result','zeroHits',resultZeroHits);
	attachEvt( "common", "locationUpdated", resultSBSubmit );
	/* do this after we have ID's so the rank for mr pages will be correct */
	attachEvt("result", "preCollectRecords", resultPaginate);
}

function resultSBSubmit(){searchBarSubmit();}

/* returns the last 'index' postion ocurring in this page */
function resultFinalPageIndex() {
	if(getHitCount() < (getOffset() + getDisplayCount())) 
		return getHitCount() - 1;
	return getOffset() + getDisplayCount() - 1;
}




/* generic search method */
function resultCollectSearchIds( type, method, handler ) {

	var sort		= (getSort() == SORT_TYPE_REL) ? null : getSort(); 
	var sortdir = (sort) ? ((getSortDir()) ? getSortDir() : SORT_DIR_ASC) : null;

	var item_type;
	var item_form;
	var args = {};

	if( type ) {
		var form = parseForm(getForm());
		item_type = form.item_type;
		item_form = form.item_form;

	} else {
		item_type = (getItemType()) ? getItemType().split(/,/) : null;
		item_form = (getItemForm()) ? getItemForm().split(/,/) : null;
	}

	var limit = (resultFetchAllRecords) ? 1000 : getDisplayCount();

	if( getOffset() > 0 ) {
		if( getHitCount() > 0 && (getOffset() + getDisplayCount()) > getHitCount() ) 
			limit = getHitCount() - getOffset();
	}

	var lasso = getLasso();

	if (lasso) args.org_unit = -lasso;
	else args.org_unit = getLocation();

	args.depth    = getDepth();
	args.limit    = limit;
	args.offset   = getOffset();
	args.visibility_limit = 3000;
    args.default_class = getStype();

	if(sort) args.sort = sort;
	if(sortdir) args.sort_dir = sortdir;
	if(item_type) args.item_type	= item_type;
	if(item_form) args.item_form	= item_form;
    if(getAvail()) args.available = 1;


	if(getFacet()) args.facets  = getFacet();

	if(getAudience()) args.audience  = getAudience().split(/,/);
	if(getLitForm()) args.lit_form	= getLitForm().split(/,/);
	if(getLanguage()) args.language	= getLanguage().split(/,/);
	if(getBibLevel()) args.bib_level	= getBibLevel().split(/,/);
	if(getCopyLocs()) args.locations	= getCopyLocs().split(/,/);
    if(getPubdBefore()) args.before = getPubdBefore();
    else if(getPubdAfter()) args.after = getPubdAfter();
    else if(getPubdBetween()) args.between = getPubdBetween().split(/,/);

	_debug('Search args: ' + js2JSON(args));
	_debug('Raw query: ' + getTerm());

	var atomfeed = "/opac/extras/opensearch/1.1/" + findOrgUnit(args.org_unit).shortname() + "/atom-full/" + getStype() + '?searchTerms=' + getTerm();
	if (args.facets) { atomfeed += ' ' + args.facets; }
	if (sort) { atomfeed += '&searchSort=' + sort; }
	if (sortdir) { atomfeed += '&searchSortDir=' + sortdir; }
	dojo.create('link', {"rel":"alternate", "href":atomfeed, "type":"application/atom+xml"}, dojo.query('head')[0]);

	var req = new Request(method, args, getTerm(), 1);
	req.callback(handler);
	req.send();
}





/* set the search result info, number of hits, which results we're 
	displaying, links to the next/prev pages, etc. */
function resultSetHitInfo() { 

	var lasso = getLasso();
	if (!lasso) {
		/* tell the user where the results are coming from */
		var baseorg = findOrgUnit(getLocation());
		var depth = getDepth();
		var mydepth = findOrgDepth(baseorg);
		if( findOrgDepth(baseorg) != depth ) {
			var tmporg = baseorg;
			while( mydepth > depth ) {
				mydepth--;
				tmporg = findOrgUnit(tmporg.parent_ou());
			}
			unHideMe($('including_results_for'));
			$('including_results_location').appendChild(text(tmporg.name()));
		}
	}


	try{searchTimer.stop()}catch(e){}

	//if( findCurrentPage() == MRESULT ) {
	if( findCurrentPage() == MRESULT || 

		(findCurrentPage() == RRESULT &&
			(
				getRtype() == RTYPE_TITLE ||
				getRtype() == RTYPE_AUTHOR ||
				getRtype() == RTYPE_SUBJECT ||
				getRtype() == RTYPE_SERIES ||
				getRtype() == RTYPE_KEYWORD 
			)

		) ) {

		if(getHitCount() <= lowHitCount && getTerm())
			runEvt('result', 'lowHits');
	}

	if(getHitCount() == 0) {
		runEvt('result', 'zeroHits');
		return;
	}


	var pages = getHitCount() / getDisplayCount();
	if(pages % 1) pages = parseInt(pages) + 1;

	

	var cpage = (getOffset()/getDisplayCount()) + 1;

	G.ui.result.current_page.appendChild(text(cpage));
	G.ui.result.num_pages.appendChild(text(pages + ")")); /* the ) is dumb */

	$('current_page2').appendChild(text(cpage));
	$('num_pages2').appendChild(text(pages + ")")); /* the ) is dumb */

	/* set the offsets */
	var offsetEnd = getDisplayCount() + getOffset();  
	if( getDisplayCount() > (getHitCount() - getOffset()))  
		offsetEnd = getHitCount();

	G.ui.result.offset_end.appendChild(text(offsetEnd));
	G.ui.result.offset_start.appendChild(text(getOffset() + 1));

	$('offset_end2').appendChild(text(offsetEnd));
	$('offset_start2').appendChild(text(getOffset() + 1));

	G.ui.result.result_count.appendChild(text(getHitCount()));
	unHideMe(G.ui.result.info);

	$('result_count2').appendChild(text(getHitCount()));
	unHideMe($('result_info_div2'));
}

function resultLowHits() {
	showCanvas();
	unHideMe($('result_low_hits'));
	if(getHitCount() > 0)
		unHideMe($('result_low_hits_msg'));

    var words = [];
    for(var key in resultCompiledSearch.searches) 
        words.push(resultCompiledSearch.searches[key].term);

	var sreq = new Request(CHECK_SPELL, words.join(' '));
	sreq.callback(resultSuggestSpelling);
	sreq.send();

    for(var key in resultCompiledSearch.searches) {
		var areq = new Request(FETCH_CROSSREF, key, resultCompiledSearch.searches[key].term);
		areq.callback(resultLowHitXRef);
		areq.send();
	}

	if( !(getForm() == null || getForm() == 'all' || getForm() == "") ) {
		var a = {};
		a[PARAM_FORM] = "all";
		$('low_hits_remove_format_link').setAttribute('href',buildOPACLink(a));
		unHideMe($('low_hits_remove_format'));
	}

	resultSuggestSearchClass();

	if(getTerm()) resultExpandSearch(); /* advanced search */
}

var lowHitsXRefSet = {};
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

            if (lowHitsXRefSet[word] == 1) continue;
            lowHitsXRefSet[word] = 1;

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
	//if(getTerm()) resultExpandSearch(); /* advanced search */
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
	var phrase = getTerm();
	var words = phrase.split(/ /);

	var newterm = "";

	for( var w = 0; w < words.length; w++ ) {
		var word = words[w];
		var blob = grep(res, function(i){return (i.word == word);});
		if( blob ) blob = blob[0];
		else continue;
		if( blob.word == word ) {
			if( !blob.found && blob.suggestions && blob.suggestions[0] ) {
				newterm += " " + blob.suggestions[0];
				unHideMe($('did_you_mean'));
			} else {
				newterm += " " + word;
			}
		}
	}

	var arg = {};
	arg[PARAM_TERM] = newterm;
	$('spell_check_link').setAttribute('href', buildOPACLink(arg));
	$('spell_check_link').appendChild(text(newterm));
}


function resultPaginate() {
	var o = getOffset();

	if( !(  ((o) + getDisplayCount()) >= getHitCount()) ) {

		var args = {};
		args[PARAM_OFFSET]	= o + getDisplayCount();
		args[PARAM_SORT]		= SORT;
		args[PARAM_SORT_DIR] = SORT_DIR;
		args[PARAM_RLIST]		= new CGI().param(PARAM_RLIST);

		G.ui.result.next_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.next_link, config.css.result.nav_active);

		$('next_link2').setAttribute("href", buildOPACLink(args)); 
		addCSSClass($('next_link2'), config.css.result.nav_active);

		args[PARAM_OFFSET] = getHitCount() - (getHitCount() % getDisplayCount());

		/* when hit count is divisible by display count, we have to adjust */
		if( getHitCount() % getDisplayCount() == 0 ) 
			args[PARAM_OFFSET] -= getDisplayCount();

        /*
		G.ui.result.end_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.end_link, config.css.result.nav_active);

		$('end_link2').setAttribute("href", buildOPACLink(args)); 
		addCSSClass($('end_link2'), config.css.result.nav_active);
        */
	}

	if( o > 0 ) {

		var args = {};
		args[PARAM_SORT]		= SORT;
		args[PARAM_SORT_DIR] = SORT_DIR;
		args[PARAM_RLIST]		= new CGI().param(PARAM_RLIST);

		args[PARAM_OFFSET] = o - getDisplayCount();
		G.ui.result.prev_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.prev_link, config.css.result.nav_active);

		$('prev_link2').setAttribute( "href", buildOPACLink(args)); 
		addCSSClass($('prev_link2'), config.css.result.nav_active);

		args[PARAM_OFFSET] = 0;
		G.ui.result.home_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.home_link, config.css.result.nav_active);

		$('search_home_link2').setAttribute( "href", buildOPACLink(args)); 
		addCSSClass($('search_home_link2'), config.css.result.nav_active);
	}

	if(getDisplayCount() < getHitCount()) {
		unHideMe($('start_end_links_span'));
		unHideMe($('start_end_links_span2'));
   }

	showCanvas();
	try{searchTimer.stop()}catch(e){}
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

function unhideGoogleBooksLink (data) {
    for ( var i in data ) {
        //if (data[i].preview == 'noview') continue;

        var gbspan = $n(document.documentElement, 'googleBooksLink-' + i);
        var gba = $n(gbspan, "googleBooks-link");

        gba.setAttribute(
            'href',
            data[i].info_url
        );
        removeCSSClass( gbspan, 'hide_me' );
    }
}

/* display the record info in the record display table 'pos' is the 
		zero based position the record should have in the display table */
function resultDisplayRecord(rec, pos, is_mr) {

    fieldmapper.IDL.load(['mvr']);
	if(rec == null) rec = new mvr(); /* so the page won't die if there was an error */
	recordsHandled++;
	recordsCache.push(rec);

	var r = table.rows[pos + 1];
    var currentISBN = cleanISBN(rec.isbn());

    if (googleBooksLink) {
	    var gbspan = $n(r, "googleBooksLink");
        if (currentISBN) {
            gbspan.setAttribute(
                'name',
                gbspan.getAttribute('name') + '-' + currentISBN
            );

            if (isbnList) isbnList += ', ';
            isbnList += currentISBN;
        }
    }

    if (currentISBN && chilifresh && chilifresh != '(none)') {
        var cfrow = $n(r, "chilifreshReview");
        if (cfrow) {
            removeCSSClass( cfrow, 'hide_me' );
        }
        var cflink = $n(r, "chilifreshReviewLink");
        if (cflink) {
            cflink.setAttribute(
                'id',
                'isbn_' + currentISBN
            );
        }
        var cfdiv = $n(r, "chilifreshReviewResult");
        if (cfdiv) {
            cfdiv.setAttribute(
                'id',
                'chili_review_' + currentISBN
            )
        }
    }

/*
	try {
		var rank = parseFloat(ranks[pos + getOffset()]);
		rank		= parseInt( rank * 100 );
		var relspan = $n(r, "relevancy_span");
		relspan.appendChild(text(rank));
		unHideMe(relspan.parentNode);
	} catch(e){ }
*/

	var pic = $n(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(currentISBN));

	var title_link = $n(r, config.names.result.item_title);
	var author_link = $n(r, config.names.result.item_author);

	var onlyrec;
	if( is_mr )  {
		onlyrec = onlyrecord[ getOffset() + pos ];
		if(onlyrec) {
			buildunAPISpan($n(r,'unapi'), 'biblio-record_entry', onlyrec);

			var args = {};
			args.page = RDETAIL;
			args[PARAM_OFFSET] = 0;
			args[PARAM_RID] = onlyrec;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
			title_link.setAttribute("href", buildOPACLink(args));
			title_link.appendChild(text(normalize(truncate(rec.title(), 65))));

		} else {
			buildunAPISpan($n(r,'unapi'), 'metabib-metarecord', rec.doc_id());

			buildTitleLink(rec, title_link); 
			var args = {};
			args.page = RRESULT;
			args[PARAM_OFFSET] = 0;
			args[PARAM_MRID] = rec.doc_id();
			pic.parentNode.setAttribute("href", buildOPACLink(args));
		}

		unHideMe($n(r,'place_hold_span'));
		$n(r,'place_hold_link').onclick = function() { resultDrawHoldsWindow(rec.doc_id(), 'M'); }
            

	} else {
		onlyrec = rec.doc_id();
		buildunAPISpan($n(r,'unapi'), 'biblio-record_entry', rec.doc_id());

		buildTitleDetailLink(rec, title_link); 
		var args = {};
		args.page = RDETAIL;
		args[PARAM_OFFSET] = 0;
		args[PARAM_RID] = rec.doc_id();
		pic.parentNode.setAttribute("href", buildOPACLink(args));

		unHideMe($n(r,'place_hold_span'));
		$n(r,'place_hold_link').onclick = function() { resultDrawHoldsWindow(rec.doc_id(), 'T'); }
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

		if(!isNull(rec.physical_description()) ) {
			unHideMe( $n(r, "result_table_extra_span"));
			var t = " " + rec.physical_description();
			//$n(r, "result_table_phys_span").appendChild( text(t.replace(/:.*/g,'')));
			$n(r, "result_table_phys_span").appendChild( text(t));
		}

	}

	resultBuildFormatIcons( r, rec, is_mr );

	var bt_params = {
		sync			: false,
		root			: r,
		subObjectLimit  : 10,
		org_unit		: findOrgUnit(getLocation()).shortname(),
		depth			: getDepth()
	};

	if (!is_mr) {
		bt_params = dojo.mixin( bt_params, { record : onlyrec } );
	} else {
		bt_params = dojo.mixin( bt_params, { metarecord : onlyrec } );
	}

	if (findOrgType(findOrgUnit(getLocation()).ou_type()).can_have_vols())
		unHideMe($n(r,'local_callnumber_list'));

	new openils.BibTemplate( bt_params ).render();

	unHideMe(r);
	
	runEvt("result", "recordDrawn", rec.doc_id(), title_link);

	/*
	if(resultPageIsDone())  {
		runEvt('result', 'allRecordsReceived', recordsCache);
	}
	*/
}

function resultDrawHoldsWindow(hold_target, hold_type) {
    var src = location.href;

    if(forceLoginSSL && src.match(/^http:/)) {

        src = src.replace(/^http:/, 'https:');

        if(src.match(/&hold_target=/)) {
            src.replace(/&hold_target=(\d+)/, hold_target);

        } else {
            src += '&hold_target=' + hold_target;
        }

        location.href = src;

    } else {
        holdsDrawEditor({record:hold_target, type:hold_type});
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


function resultBuildFormatIcons( row, rec, is_mr ) {

	var ress = rec.types_of_resource();

	for( var i in ress ) {

		var res = ress[i];
		if(!res) continue;

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

		if(is_mr) {
			args.page = RRESULT;
			args[PARAM_TFORM] = modsFormatToMARC(res);
			args[PARAM_MRID] = rec.doc_id();

		} else {
			args.page = RDETAIL
			args[PARAM_RID] = rec.doc_id();
		}

		link.setAttribute("href", buildOPACLink(args));

	}
}

function fetchGoogleBooksLink () {
    if (isbnList && googleBooksLink) {
        var scriptElement = document.createElement("script");
        scriptElement.setAttribute("id", "jsonScript");
        scriptElement.setAttribute("src",
            "http://books.google.com/books?bibkeys=" + 
            escape(isbnList) + "&jscmd=viewapi&callback=unhideGoogleBooksLink");
        scriptElement.setAttribute("type", "text/javascript");
        // make the request to Google Book Search
        document.documentElement.firstChild.appendChild(scriptElement);
    }
}

function fetchChiliFreshReviews() {
    if (chilifresh && chilifresh != '(none)') {
        try { chili_init(); } catch(E) { console.log(E + '\n'); }
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
	var start_here = 0;
	var orgHiding = checkOrgHiding();
	if (orgHiding) {
		for (var i = 0; i < nodes.length; i++) {
			if (orgHiding.depth == findOrgDepth(nodes[i])) {
				start_here = i;
			}
		}
	}

	var node = nodes[start_here];
	var type = findOrgType(node.ou_type());
	ccell.id = "copy_count_cell_" + type.depth() + "_" + pagePosition;
	ccell.title = type.opac_label();
	//addCSSClass(ccell, config.css.result.cc_cell_even);

	var lastcell = ccell;
	var lastheadcell = null;

	var cchead = null;
	var ccheadcell = null;
	if(!resultCCHeaderApplied && !getLasso()) {
		ccrow = $('result_thead_row');
		ccheadcell =  ccrow.removeChild($n(ccrow, "result_thead_ccell"));
		var t = ccheadcell.cloneNode(true);
		lastheadcell = t;
		t.appendChild(text(type.opac_label()));
		ccrow.appendChild(t);
		resultCCHeaderApplied = true;
	}

	if(nodes[start_here+1]) {

		var x = start_here+1;
		var d = findOrgDepth(nodes[start_here+1]);
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

	var loc = getLasso();
	if (loc) loc = -loc;
	else loc= getLocation();

	var req = new Request(methodName, loc, rec.doc_id(), getForm() );
	req.request.userdata = [ rec, pagePosition ];
	req.callback(resultHandleCopyCounts);
	req.send();
}

function resultHandleCopyCounts(r) {
	runEvt('result', 'copyCountsReceived', r.userdata[0], r.userdata[1], r.getResultObject()); 
}


/* XXX Needs to understand Lasso copy counts... */
/* display the collected copy counts */
function resultDisplayCopyCounts(rec, pagePosition, copy_counts) {
	if(copy_counts == null || rec == null) return;

	if (getLasso()) {
		var copy_counts_lasso = {
			transcendant : null,
			count : 0,
			unshadow : 0,
			available : 0,
			depth : -1,
			org_unit : getLasso()
		};

		for (var i in copy_counts) {
			copy_counts_lasso.transcendant = copy_counts[i].transcendant;
			copy_counts_lasso.count += parseInt(copy_counts[i].count);
			copy_counts_lasso.unshadow += parseInt(copy_counts[i].unshadow);
			copy_counts_lasso.available += parseInt(copy_counts[i].available);
		}

		copy_counts = [ copy_counts_lasso ];
	}

	var i = 0;
	while(copy_counts[i] != null) {
		var cell = $("copy_count_cell_" + i +"_" + pagePosition);
		if (cell) {
			var cts = copy_counts[i];
			cell.appendChild(text(cts.available + " / " + cts.count));

			if(isXUL()) {
				/* here we style opac-invisible records for xul */

				if( cts.depth == 0 ) {
					if(cts.transcendant == null && cts.unshadow == 0) {
						_debug("found an opac-shadowed record: " + rec.doc_id());
						var row = cell.parentNode.parentNode.parentNode.parentNode.parentNode; 
						if( cts.count == 0 ) 
							addCSSClass( row, 'no_copies' );
						else 
							addCSSClass( row, 'shadowed' );
					}
				}
			}
		}
		i++;
	}
}



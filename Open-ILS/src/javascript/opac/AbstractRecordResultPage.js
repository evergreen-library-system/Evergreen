
AbstractRecordResultPage.prototype					= new Page();
AbstractRecordResultPage.prototype.constructor	= AbstractRecordResultPage;
AbstractRecordResultPage.baseClass					= Page.constructor;


/* constructor for our singleton object */
function AbstractRecordResultPage() {}


/* initialize all of the UI components and set up data structures */
AbstractRecordResultPage.prototype.init = function() {

	debug( "Initing an AbstractRecordResultPage" );

	/* included page chunks */
	this.searchBar			= new SearchBarChunk();

	/* UI objects */
	this.recordBox			= getById("record_result_box");

	this.authorBox = new Box();
	this.authorBox.init("Relevant Authors", true, true, 15);
	this.authorBox.sortByCount();

	this.subjectBox = new Box();
	this.subjectBox.init("Relevant Subjects", true, true, 15);
	this.subjectBox.sortByCount();

	this.sidebarBox		= getById("record_sidebar_box");


	this.hitsPerPage		= 8;	 /* how many hits are displayed per page */
	this.resetPage();

	this.searchDepth		= 0; /* default to the current search location */
	this.statusBar			= getById("top_status_bar_table");
	this.theadDrawn		= false;
	this.bigOlBox			= getById("big_ol_box");

}



/** Resets data structures for a new search */
AbstractRecordResultPage.prototype.resetPage = function() {
	this.searchBar.reset();
	var spot = getById("progress_bar_location");
	var spot2 = getById("progress_bar_percent_location");
	if(spot) {
		while(spot.lastChild) 
			spot.removeChild(spot.lastChild);

		/* progress items for each record and it's hit count listing */
		this.progressBar = new ProgressBar(parseInt(this.hitsPerPage) * 2);
		spot.appendChild(this.progressBar.getNode());
	}
	if(spot2 && this.progressBar)
		spot2.appendChild(this.progressBar.percentDiv);
	this.received = 0;

	this.requestBatch = new RequestBatch();
	this.finalized = false;
}

AbstractRecordResultPage.prototype.resetSearch = function() {
	this.recordIDs				= new Array();
	this.ranks					= new Array();
	this.hitCount				= 0;					/* hits for the current search */
	this.searchOffset			= 0;					/* the offset for the search display */

}

AbstractRecordResultPage.prototype.gatherIDs = function(result) {

	this.hitCount = parseInt(result.count);
	if(this.hitCount < 1 ) {
		this.finalizePage();
		return false;
	}
	

	/* the 'ids' field consist of [record, rank] */
	/* gather all of the ID's */
	if( result.ids  && typeof result.ids == 'object' 
			&& result.ids[0] != null
			&& result.ids[0].constructor == Array ) {

		for( var i in result.ids ) {
			if(result.ids[i]==null || result.ids[i][0] == null) break;
			var offset = parseInt(i) + parseInt(this.searchOffset);
			this.recordIDs[offset] = result.ids[i][0];
			this.ranks[offset] = parseFloat(result.ids[i][1]);
			/*
			debug("adding ranks[" + offset + "] = " + result.ids[i][1] + 
					"  \nrecordIDs["+offset+"], result.ids["+i+"][0]");
					*/
		}

	} else {

		for( var i in result.ids ) {
			if(result.ids[i]==null) break;
			var offset = parseInt(i) + parseInt(this.searchOffset);
			this.recordIDs[offset] = result.ids[i];
			debug("adding recordIDs["+offset+"], result.ids["+i+"]");
		}
	}

	return true;
}



AbstractRecordResultPage.prototype.complete = function() {

}


AbstractRecordResultPage.prototype.displayRecord = 
	function( record, search_id, page_id ) {

	if(page_id == 0)
		this.buildNextLinks();

	this.received += 1;

	this.progressBar.manualNext();

	var id = parseInt(page_id);
	var title_row = table_row_find_or_create(this.recordBox, id * 2 + 1 );
	var author_row = table_row_find_or_create(this.recordBox, id * 2 + 2 );

	author_row.id = "record_result_author_row_" + id;
	title_row.id = "record_result_title_row_" + id;

	/* build the appropriate context node for this result */
	var menu = globalMenuManager.buildMenu(
		"record_result_row_" + page_id );

	this.addMenuItems( menu, record );
	globalMenuManager.setContext(title_row, menu);
	globalMenuManager.setContext(author_row, menu);
	getDocument().body.appendChild(menu.getNode());
	/* ------------------------------------ */


	var isbn = record.isbn();
	if(isbn) isbn = isbn.replace(/\s+/,"");
	else isbn = "";

	var pic_cell = title_row.insertCell(0);
	pic_cell.setAttribute("rowspan","2");
	pic_cell.rowSpan = 2;


	var rankBox = "";
	if( this.ranks.length > 0 ) {
		var x = (parseInt(this.page) * parseInt(this.hitsPerPage)) + parseInt(page_id);
		var per = parseInt(this.ranks[x] / this.ranks[0] * 100.0);
		rankBox = "<div class='relevance_box'><div style='width:" + 
			per + "%' class='relevance'>&nbsp;</div></div>";
	}
			

	/* pull from amazon for now... */
	pic_cell.innerHTML = rankBox + 
		"<img height='50' width='45' src='http://images.amazon.com/images/P/" 
		+ isbn + ".01.MZZZZZZZ.jpg'>";


	var title_cell = title_row.insertCell(title_row.cells.length);
	title_cell.id = "record_result_title_box_" + id;
	add_css_class( title_cell, "record_result_title_box");

	var author_cell = author_row.insertCell(author_row.cells.length);
	author_cell.id = "record_result_author_box_" + id;
	add_css_class(author_cell, "record_result_author_box");


	/* limit the length of the title and author lines */
	var tlength = 100;

	if( record.title() ) {
		if(record.title().length > tlength) {
			record.title(record.title().substr(0,tlength));
			record.title(record.title() + "...");
		}
		record.title(normalize(record.title()));
	}

	if( record.author() ) {
		if(record.author().length > tlength) {
			record.author( record.author().substr(0,tlength));
			record.author(record.author() + "...");
		}
		record.author(normalize(record.author()));
	}	

	title_cell.appendChild(this.mkLink(record.doc_id(), "title", record.title()));
	author_cell.innerHTML = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
	author_cell.appendChild(this.mkLink(record.doc_id(), "author", record.author()));

	var classname = "result_even";
	if((page_id%2) != 0) 
		classname = "result_odd";

	add_css_class(title_row, classname);
	add_css_class(author_row, classname);

	/* now grab the record authors and subjects */
	if( record.author() ) {
		this.authorBox.addItem( this.mkAuthorLink(record.author()), record.author() );
	}

	/* gather the subjects.  subjects are either a string or an array of
		[subject, broader topic].  currently, they're all just treated like
		subjects */
	var arr = record.subject();
	for( var sub in arr ) {

		var ss = arr[sub];
		if( ss.constructor != Array )
			ss = [ss];

		for( var i in ss ) {
			var s = normalize(ss[i]);
			this.subjectBox.addItem( this.mkSubjectLink(s), s );
		}
	}

	/* requestBatch will only have one request in it when the current
		record is the last record requested */
	if( this.requestBatch.pending() < 2  )
		this.finalizePage();
}

AbstractRecordResultPage.prototype.mkAuthorLink = function(auth) {
	var href = createAppElement("a");
	add_css_class(href,"record_result_sidebar_link");
	href.setAttribute("href",
		"?target=mr_result&mr_search_type=author&page=0&mr_search_query=" +
		encodeURIComponent(auth));
	href.appendChild(createAppTextNode(auth));
	return href;
}

AbstractRecordResultPage.prototype.mkSubjectLink = function(sub) {
	var href = createAppElement("a");
	add_css_class(href,"record_result_sidebar_link");
	href.setAttribute("href",
		"?target=mr_result&mr_search_type=subject&page=0&mr_search_query=" +
		encodeURIComponent(sub));
	href.appendChild(createAppTextNode(sub));
	return href;
}

AbstractRecordResultPage.prototype.finalizePage = function() {

	if( this.finalized )
		return;
	this.finalized = true;

	this.subjectBox.finalize();
	this.authorBox.finalize();

	this.sidebarBox.appendChild(this.subjectBox.getNode());
	this.sidebarBox.appendChild(createAppElement("br"));
	this.sidebarBox.appendChild(this.authorBox.getNode());
	this.sidebarBox.appendChild(createAppElement("br"));

//	showMe(this.buttonsBox);

	var ses = UserSession.instance().getSessionId();
	var box = this.sidebarBox;

	if(ses) {
		Survey.retrieveOpacRandom(ses, 
			function(sur) { 
				sur.setSubmitCallback(
					function() { alert("Thanks!"); return true; });
				box.appendChild( sur.getNode() ); 
				sur.setHidden(false);
			}
		);
	} else {
		Survey.retrieveOpacRandomGlobal( 
			function(sur) { 
				sur.setSubmitCallback(
					function() { alert("Thanks!"); return true; });
				box.appendChild( sur.getNode() ); 
				sur.setHidden(false);
			}
		);
	}


	if(this.hitCount < 1)
		if(this.progressBar) this.progressBar.stop();

	/* in case we're hidden */
	showMe(this.bigOlBox);

}


AbstractRecordResultPage.prototype.displayCopyCounts = 
	function(copy_counts, search_id, page_id) {
		
	this.progressBar.manualNext();
	var titlerow  = getById("record_result_title_row_" + page_id );
	var authorrow  = getById("record_result_author_row_" + page_id );

	var tcell = getById("record_result_title_box_" + page_id );

	if(!this.theadDrawn) {
		var trow = getById("record_result_thead_row");
		for( var i in copy_counts) {
			var cell = trow.insertCell(trow.cells.length);
			add_css_class(cell,"record_result_thead_header");
			cell.innerHTML = 
				findOrgType(findOrgUnit(copy_counts[i].org_unit).ou_type()).name();
		}
		this.theadDrawn = true;
	}

	for( var i in copy_counts) {
		var cell = createAppElement("td");
		add_css_class(cell, "copy_count_cell");
		cell.innerHTML = copy_counts[i].available + " / " + copy_counts[i].count;
		cell.setAttribute("rowspan","2");
		cell.rowSpan = 2;
		titlerow.appendChild(cell);
	}

	if(page_id  == (parseInt(this.hitsPerPage) - 1) ) {
		if(this.progressBar) this.progressBar.stop();
	}

	if( (page_id  == ((parseInt(this.hitCount) - 1 ) - parseInt(this.searchOffset))) ||
			(page_id == (parseInt(this.hitsPerPage) - 1) )) 
		if(this.progressBar) this.progressBar.stop();
}



AbstractRecordResultPage.prototype.buildNextLinks = function() {


	var obj = this;
	var next;
	var prev;

	debug("Building links");
	if( this.searchOffset < (parseInt(this.hitCount) - this.hitsPerPage)) {
		next = createAppElement("a");
		add_css_class(next,"record_next_button");
		add_css_class(next,"record_next_button_active");
		next.href = "javascript:globalPage.next();";
	} else {
		next = createAppElement("span");
		add_css_class(next,"record_next_button_inactive");
	}

	if(this.searchOffset > 0) {
		prev = createAppElement("a");
		add_css_class(prev,"record_next_button");
		add_css_class(prev,"record_next_button_active");
		prev.href = "javascript:globalPage.prev();";
	} else {
		prev = createAppElement("span");
		add_css_class(prev,"record_next_button_inactive");
	}

	next.appendChild(createAppTextNode("Next"));
	prev.appendChild(createAppTextNode("Previous"));


	var i = this.searchOffset;
	var max = parseInt(i) + this.hitsPerPage;
	if( max > this.hitCount )
		max = this.hitCount;

	var hcell = getById("hit_count_cell");

	hcell.appendChild(
		createAppTextNode( "Displaying " + 
		( parseInt(i) + 1 ) + " to " + max + " of " + this.hitCount));

	hcell.appendChild(createAppTextNode(" "));

	hcell.appendChild( prev );
	var span = createAppElement("span");
	span.appendChild(createAppTextNode(" ... "));
	hcell.appendChild(span);
	hcell.appendChild( next );

	
}




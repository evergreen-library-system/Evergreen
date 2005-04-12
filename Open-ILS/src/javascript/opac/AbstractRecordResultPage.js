
AbstractRecordResultPage.prototype					= new Page();
AbstractRecordResultPage.prototype.constructor	= AbstractRecordResultPage;
AbstractRecordResultPage.baseClass					= Page.constructor;


/* constructor for our singleton object */
function AbstractRecordResultPage() { }


/* initialize all of the UI components and set up data structures */
AbstractRecordResultPage.prototype.init = function() {

	debug( "Initing an AbstractRecordResultPage" );

	/* included page chunks */
	//this.searchBarForm = new JSSearchBarFormChunk();
	this.searchBar		= new SearchBarChunk();

	/* UI objects */
	this.buttonsBox		= document.getElementById("record_next_prev_links_box");
	this.prevButton		= document.getElementById("record_prev_button");
	this.nextButton		= document.getElementById("record_next_button");
	this.recordBox			= document.getElementById("record_result_box");


	this.collectedSubjects	= new Array();		/* subjects attached to the current batch of records */
	this.collectedAuthors	= new Array();		/* subjects attached to the current batch of records */
	this.requestBatch			= new Array();		/* current batch of RemoteRequest objects */
	this.recordIDs				= new Array();		/* this set of ids for this search */
	this.hitCount				= 0;					/* hits for the current search */
	this.searchOffset			= 0;					/* the offset for the search display */
	this.hitsPerPage			= 10;					/* how many hits are displayed per page */
	
}


AbstractRecordResultPage.prototype.next = function() {
	this.searchOffset += parseInt(this.hitsPerPage);
	debug("Set searchOffset to " + this.searchOffset );

	/* see if we need to retrieve them */
	if( this.recordIDs[this.searchOffset] != null &&
		this.recordIDs[this.searchOffset - this.hitsPerPage] != null ) {
		debug("Not Calling Search");
		this.reset();
		this.collectRecords();
	} else {
		this.doSearch(true);
	}

}

AbstractRecordResultPage.prototype.prev = function() {
	this.searchOffset -= this.hitsPerPage;


	if( this.recordIDs[this.searchOffset] != null &&
		this.recordIDs[this.searchOffset + this.hitsPerPage] != null ) {
		this.reset();
		this.collectRecords();
	} else {
		this.doSearch(true);
	}
}




/** Resets data structures for a new search */
AbstractRecordResultPage.prototype.reset = function() {

	while(this.recordBox.rows.length > 0)
		this.recordBox.deleteRow(-1);

	this.prevButton.style.visibility = "hidden";
	this.nextButton.style.visibility = "hidden";
	this.buttonsBox.style.visibility = "hidden";
}

AbstractRecordResultPage.prototype.resetSearch = function() {
	this.recordIDS = new Array();
}

AbstractRecordResultPage.prototype.gatherIDs = function(result) {

	this.hitCount = result.count;

	/* gather all of the ID's */
	for( var i in result.ids ) {
		if(result.ids[i]==null) break;
		var offset = parseInt(i) + parseInt(this.searchOffset);
		this.recordIDs[offset] = result.ids[i];
		debug("adding recordIDs["+offset+"], result.ids["+i+"]");
	}

}


/* search_id is where we are in the recordID's array.  page_id is where we 
	are in relation to the current page [ 0 .. hitsPerPage ]
	*/
AbstractRecordResultPage.prototype.displayRecord = function( record, search_id, page_id ) {

	result_row = new RecordResultRow(page_id);
	var row = table_row_find_or_create(
			this.recordBox, parseInt(page_id) * 3 );
	row.appendChild(result_row.obj);

	/* this is for our row of XUL buttons.  If no buttons are necessary, this just acts as
		a blank row for visual spacing */
	var xul_row = table_row_find_or_create(this.recordBox, (parseInt(page_id) * 3) + 1 );
	var xul_cell = table_cell_find_or_create( xul_row, 0 );

	var blank_row = table_row_find_or_create(this.recordBox, (parseInt(page_id) * 3) + 2 );
	var blank_cell = table_cell_find_or_create( blank_row, 0 );
	blank_cell.innerHTML = "<br/>";

	add_css_class( xul_cell, "record_result_xul_button_box" );
	add_css_class( xul_cell, "xul" );
	xul_cell.id = "record_result_xul_button_box_" + page_id;



	var title_box	= document.getElementById("record_result_title_box_" + page_id );
	var author_box = document.getElementById("record_result_author_box_" + page_id );
	var row			= document.getElementById("record_result_row_box_" + page_id );
	var xul			= document.getElementById("record_result_xul_button_box_" + page_id );


	debug("displayRecord " + record.doc_id );

	try {
		xulEvtRecordResultButton( globalPageTarget, xul, record, search_id, page_id );
	} catch(E) {
		debug("xul function error: " + E );
	}

	debug( "Displaying record title: " + record.title + " author: " + record.author );

	/* limit the length of the title and author lines */
	var tlength = 100;

	if(record.title.length > tlength) {
		record.title = record.title.substr(0,tlength);
		record.title += "...";
	}

	if(record.author.length > tlength) {
		record.author = record.author.substr(0,tlength);
		record.author += "...";
	}

	title_box.appendChild( document.createTextNode(
				(parseInt(search_id) + 1)  + ".   "));
	title_box.appendChild( 
		this.mkLink(record.doc_id, "title", record.title));

	author_box.appendChild(
		this.mkLink(record.doc_id, "author", record.author));

	var classname = "result_even";
	if((page_id%2) != 0) 
		classname = "result_odd";
	add_css_class(row, classname);


	/* after loading the last record, contine building the page */
	debug( "Pageid : " + page_id + " hitsperpage: " + this.hitsPerPage );

	if( page_id  == (this.hitsPerPage - 1)) {

		/* do we need next/prev buttons */
		this.buttonsBox.style.visibility = "visible";
		if( this.searchOffset < (parseInt(this.hitCount) - this.hitsPerPage)) 
			this.nextButton.style.visibility = "visible";
		if(this.searchOffset > 0) 
			this.prevButton.style.visibility = "visible";
	}

}

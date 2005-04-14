
AbstractRecordResultPage.prototype					= new Page();
AbstractRecordResultPage.prototype.constructor	= AbstractRecordResultPage;
AbstractRecordResultPage.baseClass					= Page.constructor;


/* constructor for our singleton object */
function AbstractRecordResultPage() {

}


/* initialize all of the UI components and set up data structures */
AbstractRecordResultPage.prototype.init = function() {

	debug( "Initing an AbstractRecordResultPage" );

	/* included page chunks */
	this.searchBar			= new SearchBarChunk();

	/* UI objects */
	this.buttonsBox		= getById("record_next_prev_links_box");
	this.prevButton		= getById("record_prev_button");
	this.nextButton		= getById("record_next_button");
	this.recordBox			= getById("record_result_box");

	this.subBox				= getById("record_subject_sidebar_box");
	this.authBox			= getById("record_author_sidebar_box");

	this.hitsPerPage		= 10;	 /* how many hits are displayed per page */
	this.resetPage();

	/*
	var tab = this.recordBox;
	var tr = globalAppFrame.createAppElement("tr");
	var cell = tr.appendChild(globalAppFrame.createAppElement("td"));
	tab.appendChild(tr);
	alert(tab.innerHTML);
	*/
}



/** Resets data structures for a new search */
AbstractRecordResultPage.prototype.resetPage = function() {

	while(this.recordBox.rows.length > 0)
		this.recordBox.deleteRow(-1);

	this.prevButton.style.visibility = "hidden";
	this.nextButton.style.visibility = "hidden";
	this.buttonsBox.style.visibility = "hidden";

	this.subBox.innerHTML				= "";
	this.authBox.innerHTML				= "";
	this.subBox.style.visibility		= "hidden";
	this.authBox.style.visibility		= "hidden";

	this.collectedSubjects				= new Array();
	this.collectedAuthors				= new Array();
}

AbstractRecordResultPage.prototype.resetSearch = function() {
	this.recordIDS				= new Array();
	this.collectedSubjects	= new Array();		/* subjects attached to the current batch of records */
	this.collectedAuthors	= new Array();		/* subjects attached to the current batch of records */
	this.requestBatch			= new Array();		/* current batch of RemoteRequest objects */
	this.recordIDs				= new Array();		/* this set of ids for this search */
	this.hitCount				= 0;					/* hits for the current search */
	this.searchOffset			= 0;					/* the offset for the search display */

}

AbstractRecordResultPage.prototype.gatherIDs = function(result) {

	this.hitCount = parseInt(result.count);

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


	var title_row = table_row_find_or_create(
			this.recordBox, parseInt(page_id) * 3 );

	var result_row_stuff = new RecordResultRow(page_id, title_row);
	//appendChild( title_row, result_row_stuff.obj );
	title_row.appendChild( result_row_stuff.obj );

	
	//addResultRow(title_row);


	//alert( title_row.innerHTML );

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

	var title_box	= getById("record_result_title_box_" + page_id );
	var author_box = getById("record_result_author_box_" + page_id );
	var row			= getById("record_result_row_box_" + page_id );
	var xul			= getById("record_result_xul_button_box_" + page_id );

	if(!title_box)
		alert("No title box");

	if(!author_box)
		alert("no author box");



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
	record.title = normalize(record.title);

	if(record.author.length > tlength) {
		record.author = record.author.substr(0,tlength);
		record.author += "...";
	}
	record.author = normalize(record.author);


	title_box.appendChild(createAppTextNode((parseInt(search_id) + 1)  + ".   "));
	title_box.appendChild(this.mkLink(record.doc_id, "title", record.title));
	author_box.appendChild(this.mkLink(record.doc_id, "author", record.author));

	var classname = "result_even";
	if((page_id%2) != 0) 
		classname = "result_odd";

	debug("Row: " +  row);
	add_css_class(row, classname);



	/* now grab the record authors and subjects */
	this.collectedAuthors[record.author] = true;	
	var arr = record.subject;
	for( var sub in arr ) {
		var s = normalize(arr[sub]);
		if( this.collectedSubjects[s])
			this.collectedSubjects[s] += 1;
		else
			this.collectedSubjects[s] = 1;
	}

	/* after loading the last record, contine building the page */

	if( (page_id  == ((parseInt(this.hitCount) - 1 ) + parseInt(this.searchOffset))) ||
			(page_id == (parseInt(this.hitsPerPage) - 1) )) 
		this.finalizePage();
}

AbstractRecordResultPage.prototype.finalizePage = function() {
	/* sort the arrays */
	this.collectedSubjects.sort();
	this.collectedAuthors.sort();

	this.subBox.style.visibility = "visible";
	this.authBox.style.visibility = "visible";

	var counter = 0;

	for(var sub in this.collectedSubjects) {
		if(counter++ > 10)
			break;
		var href = createAppElement("a");
		add_css_class(href,"record_result_sidebar_link");
		href.setAttribute("href","?target=mr_result&mr_search_type=subject&page=0&mr_search_query=" +
				      encodeURIComponent(sub));
		href.appendChild(createAppTextNode(sub));
		this.subBox.appendChild(href);
		//this.subBox.appendChild(new LineDiv("big").obj);
		this.subBox.innerHTML += "<br/>";
	}

	counter = 0;
	for(var auth in this.collectedAuthors) {
		if(counter++ > 10)
			break;
		var href = createAppElement("a");
		add_css_class(href,"record_result_sidebar_link");
		href.setAttribute("href","?target=mr_result&mr_search_type=author&page=0&mr_search_query=" +
				      encodeURIComponent(auth));
		href.appendChild(createAppTextNode(auth));
		this.authBox.appendChild(href);
		//this.authBox.appendChild(new LineDiv("small").obj);
	}

	/* do we need next/prev buttons */
	this.buttonsBox.style.visibility = "visible";
	if( this.searchOffset < (parseInt(this.hitCount) - this.hitsPerPage)) 
		this.nextButton.style.visibility = "visible";
	if(this.searchOffset > 0) 
		this.prevButton.style.visibility = "visible";

	/*
	if( this.progressBar ) 
		this.progressBar.progressStop();
		*/

	/* now add the subjects */
}


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
	this.buttonsBox		= getById("record_next_prev_links_box_1");
	this.prevButton		= getById("record_prev_button_1");
	this.nextButton		= getById("record_next_button_1");
	this.recordBox			= getById("record_result_box");

	this.subBox				= getById("record_subject_sidebar_box");
	this.authBox			= getById("record_author_sidebar_box");

	this.hitsPerPage		= 8;	 /* how many hits are displayed per page */
	this.resetPage();

	this.searchDepth		= 0; /* default to the current search location */

	this.statusBar			= getById("top_status_bar_table");

	this.theadDrawn		= false;

	this.bigOlBox			= getById("big_ol_box");

}



/** Resets data structures for a new search */
AbstractRecordResultPage.prototype.resetPage = function() {

	/*
	while(this.recordBox.rows.length > 0)
		this.recordBox.deleteRow(-1);
		*/

	this.prevButton.style.visibility = "hidden";
	this.nextButton.style.visibility = "hidden";
	this.buttonsBox.style.visibility = "hidden";

	//this.prevButton0.style.visibility = "hidden";
	//this.nextButton0.style.visibility = "hidden";
	//this.buttonsBox0.style.visibility = "hidden";

	this.subBox.innerHTML				= "";
	this.authBox.innerHTML				= "";
	this.subBox.style.visibility		= "hidden";
	this.authBox.style.visibility		= "hidden";

	this.collectedSubjects				= new Array();
	this.collectedAuthors				= new Array();

	this.searchBar.reset();

	/*
	this.treeBox		= getById("ot_nav_widget");
	if(this.treeBox) {
		this.treeBox.innerHTML = globalOrgTreeWidget.toString();
	}
	*/

	
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
function menu() {
	alert('swapping'); 
	swapClass(getById('record_context_menu'), 'hide_me', 'show_me' );
	return true;
}


function recordRowContextHandler(evt) {
	if(!getAppWindow().event) { getAppWindow().event = evt; };
	var win = getAppWindow();
	globalMenuManager.toggle(target.id);
	return false;
}



AbstractRecordResultPage.prototype.displayRecord = 
	function( record, search_id, page_id ) {


	var id = parseInt(page_id);
	var title_row = table_row_find_or_create(this.recordBox, id * 2 + 1 );
	var author_row = table_row_find_or_create(this.recordBox, id * 2 + 2 );

	author_row.id = "record_result_author_row_" + id;
	title_row.id = "record_result_title_row_" + id;

	/* build the appropriate context node for this result */
	var menu = globalMenuManager.buildMenu(
		"record_result_row","record_result_row_" + page_id );
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


	pic_cell.innerHTML = 
		"<img height='60' width='45' src='http://images.amazon.com/images/P/" 
		+ isbn + ".01.MZZZZZZZ.jpg'>";


	var title_cell = title_row.insertCell(title_row.cells.length);
	title_cell.id = "record_result_title_box_" + id;
	add_css_class( title_cell, "record_result_title_box");

	var author_cell = author_row.insertCell(author_row.cells.length);
	author_cell.id = "record_result_author_box_" + id;
	add_css_class(author_cell, "record_result_author_box");


	if(!title_cell)
		alert("No title box");

	if(!author_cell)
		alert("no author box");

	/*
	try {
		xulEvtRecordResultButton( globalPageTarget, xul, record, search_id, page_id );
	} catch(E) {
		debug("xul function error: " + E );
	}
	*/

	debug( "Displaying record title: " + record.title() + " author: " + record.author() );

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

	//title_cell.appendChild(createAppTextNode((parseInt(search_id) + 1)  + ".   "));
	title_cell.appendChild(this.mkLink(record.doc_id(), "title", record.title()));
	author_cell.innerHTML = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
	author_cell.appendChild(this.mkLink(record.doc_id(), "author", record.author()));

	var classname = "result_even";
	if((page_id%2) != 0) 
		classname = "result_odd";

	add_css_class(title_row, classname);
	add_css_class(author_row, classname);

	/* now grab the record authors and subjects */
	if( record.author() )
		this.collectedAuthors[record.author()] = true;	

	var arr = record.subject();
	for( var sub in arr ) {
		var s = normalize(arr[sub]);
		if( this.collectedSubjects[s])
			this.collectedSubjects[s] += 1;
		else
			this.collectedSubjects[s] = 1;
	}

	/* after loading the last record, contine building the page */

	if( (page_id  == ((parseInt(this.hitCount) - 1 ) - parseInt(this.searchOffset))) ||
			(page_id == (parseInt(this.hitsPerPage) - 1) )) 
		this.finalizePage();
}

AbstractRecordResultPage.prototype.finalizePage = function() {
	/* sort the arrays */
	this.collectedSubjects = this.collectedSubjects.sort().reverse();
	this.collectedAuthors = this.collectedAuthors.sort().reverse();

	this.subBox.style.visibility = "visible";
	this.authBox.style.visibility = "visible";

	var counter = 0;

	debug("Collected Subjects: " + this.collectedSubjects[0] + ":" + this.collectedSubjects);

	for(var sub in this.collectedSubjects) {
		debug("makeing subject link: " + sub);
		if(counter++ > 10)
			break;
		var href = createAppElement("a");
		add_css_class(href,"record_result_sidebar_link");
		href.setAttribute("href","?target=mr_result&mr_search_type=subject&page=0&mr_search_query=" +
				      encodeURIComponent(sub));
		href.appendChild(createAppTextNode(sub));
		this.subBox.appendChild(href);
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
		this.authBox.innerHTML += "<br/>";
	}

	/* do we need next/prev buttons */
	this.buttonsBox.style.visibility = "visible";

	if( this.searchOffset < (parseInt(this.hitCount) - this.hitsPerPage)) {
		this.nextButton.style.visibility = "visible";
	}
	if(this.searchOffset > 0) {
		this.prevButton.style.visibility = "visible";
	}
	
	this.bigOlBox.style.visibility = "visible";
	this.bigOlBox.style.display = "block";

	/*
	if( this.progressBar ) 
		this.progressBar.progressStop();
		*/

	/* now add the subjects */

	this.surveyBox = getById("record_survey_sidebar_box");
	this.surveyBox.style.visibility = "visible";
	var ses = UserSession.instance().getSessionId();
	if(ses) {
		var surveys = Survey.retrieveAll(ses);
		for( var i in surveys ) {
			bc(this.surveyBox,surveys[i]);
		}
	}
}


function bc(box, survey) {
	var name = survey.getName();
	survey.setAction( function() { alert("Submitted Survey: " + name); } );
	box.appendChild( survey.getNode() );
}


AbstractRecordResultPage.prototype.displayCopyCounts = 
	function(copy_counts, search_id, page_id) {
		
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
		//var cell = titlerow.insertCell(titlerow.cells.length);
		var cell = createAppElement("td");
		add_css_class(cell, "copy_count_cell");
		cell.innerHTML = copy_counts[i].available + " / " + copy_counts[i].count;
		cell.setAttribute("rowspan","2");
		cell.rowSpan = 2;
		titlerow.appendChild(cell);
		/*
		titlerow.innerHTML = titlerow.innerHTML + "<td clas='copy_count_cell' rowspan='2'>" + 
			 copy_counts[i].available + " / " + copy_counts[i].count + "</td>";
			 */

	}

}




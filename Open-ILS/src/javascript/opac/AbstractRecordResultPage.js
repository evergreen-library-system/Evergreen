
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
	this.authorBox.sortByKey();

	this.subjectBox = new Box();
	this.subjectBox.init("Relevant Subjects", true, true, 15);
	this.subjectBox.sortByCount();

	this.seriesBox = new Box();
	this.seriesBox.init("Relevant Series", true, true, 15);
	this.seriesBox.sortByKey();

	this.sidebarBox		= getById("record_sidebar_box");


	if(!this.hitsPerPage)
		this.hitsPerPage		= 10;	 /* how many hits are displayed per page */

	this.resetPage();

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

	RemoteRequest.cancelAll();

	this.requestBatch = new RequestBatch();
	this.finalized = false;
	this.builtLinks = false;

	this.hitsPerPageSelector = getById('hits_per_page');

	var obj = this;
	this.hitsPerPageSelector.onchange = function() {

		var hits;
		var hits_obj = obj.hitsPerPageSelector.options[
			obj.hitsPerPageSelector.selectedIndex];	

		if(hits_obj == null)
			return;

		hits = hits_obj.value

		debug("Hits per page set to " + hits );

		obj.hitsPerPage = parseInt(hits); 	


		var location = globalSelectedLocation;
		if(location == null) location = globalLocation.id();

		url_redirect(obj.URLRefresh());
	}


	for( var i in this.hitsPerPageSelector.options ) {

		var hits_obj = obj.hitsPerPageSelector.options[i];
		if(hits_obj == null) continue;
		var hits = hits_obj.value;

		if( this.hitsPerPage == parseInt(hits) ) 
			this.hitsPerPageSelector.options[i].selected = true;
	}

}


AbstractRecordResultPage.prototype.resetSearch = function() {
	this.recordIDs				= new Array();
	this.ranks					= new Array();
	this.hitCount				= 0;					/* hits for the current search */
	this.searchOffset			= 0;					/* the offset for the search display */
	this.page					= 0;

}

AbstractRecordResultPage.prototype.gatherIDs = function(result) {
	if(result == null) return;

	this.hitCount = parseInt(result.count);

	if(result.ids.length < 1) {
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
			var rank = parseFloat(result.ids[i][1]);
			if(rank == 0)
				rank = 0.00000001; /* protect divide by 0 */
			this.ranks[offset] =  rank;
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

	if(record == null) return;
	debug("Displaying record " + record.doc_id());

	if(!instanceOf(record, Fieldmapper)) {
		debug(" * Received bogus record " + js2JSON(record));
		return;
	}

	if(page_id == 0)
		this.buildNextLinks();

	this.received += 1;

	this.progressBar.manualNext();

	var id = parseInt(page_id);
	var title_row = table_row_find_or_create(this.recordBox, id * 3 + 1 );
	var author_row = table_row_find_or_create(this.recordBox, id * 3 + 2 );
	var misc_row = table_row_find_or_create(this.recordBox, id * 3 + 3 );

	add_css_class(misc_row, "record_misc_row");
	add_css_class(title_row, "record_title_row");


	var c = misc_row.insertCell(0);
	/* shove in a div for each of the types of resource */
	for( var i = 0; i!= 9; i++) {
		var div = createAppElement("div");
		div.innerHTML = "&nbsp;";
		add_css_class(div, "record_resource_div");
		c.appendChild(div);
	}
	//var options_cell = misc_row.insertCell(1);

	c.className = "record_misc_cell";
	var resources = record.types_of_resource();

	for( var i in resources ) 
		this.buildResourcePic( c, resources[i]);

	author_row.id = "record_result_author_row_" + id;
	title_row.id = "record_result_title_row_" + id;

	/* build the appropriate context node for this result */
	var menu_name = "record_result_row_" + page_id;
	var menu = globalMenuManager.buildMenu(menu_name);

	this.addMenuItems( menu, record );

	globalMenuManager.setContext(title_row, menu);
	globalMenuManager.setContext(author_row, menu);
	globalMenuManager.setContext(misc_row, menu);

	getDocument().body.appendChild(menu.getNode());

	//var optionsLink = this.buildExtendedLinks(record, page_id);
	//if(optionsLink)
	//	options_cell.appendChild(optionsLink);
	/* ------------------------------------ */


	var pic_cell = title_row.insertCell(0);
	this.buildRecordImage( pic_cell, record, page_id, record.title());

	var title_cell = title_row.insertCell(title_row.cells.length);
	title_cell.id = "record_result_title_box_" + id;
	add_css_class( title_cell, "record_result_title_box");

	var author_cell = author_row.insertCell(author_row.cells.length);
	author_cell.id = "record_result_author_box_" + id;
	add_css_class(author_cell, "record_result_author_box");


	/* limit the length of the title and author lines */
	var tlength = 80;

	var title = "";
	if( record.title() ) {
		if(record.title().length > tlength) {
			record.title(record.title().substr(0,tlength));
			record.title(record.title() + "...");
		}
		title = normalize(record.title());
	}


	var author = "";
	if( record.author() ) {
		if(record.author().length > tlength) {
			record.author( record.author().substr(0,tlength));
			record.author(record.author() + "...");
		}
		author = normalize(record.author());
	}

	title_cell.appendChild(this.mkLink(record.doc_id(), "title", title, record.title() ));
	author_cell.innerHTML = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
	author_cell.appendChild(this.mkLink(record.doc_id(), "author", author ));

	if(instanceOf(this, RecordResultPage)) {
		var span = createAppElement("span");
		span.style.marginLeft = "10px";

		if(record.pubdate() || record.edition())
			span.appendChild(createAppTextNode(" -- "));

		if(record.pubdate())
			span.appendChild(createAppTextNode(" " + record.pubdate()));

		if(record.edition())
			span.appendChild(createAppTextNode(" " + record.edition()));

			author_cell.appendChild(span);
	}

	var classname = "result_even";
	if((page_id%2) != 0) 
		classname = "result_odd";

	add_css_class(title_row, classname);
	add_css_class(author_row, classname);
	add_css_class(misc_row, classname);

	/* now grab the record authors and subjects */
	if( author ) {
		this.authorBox.addItem( this.mkAuthorLink(author) , author);
	}

	/* gather the subjects.  subjects are either a string or an array of
		[subject, broader topic].  currently, they're all just treated like
		subjects */
	var arr = record.subject();
	var x = 0;
	for( var sub in arr ) {
		if(x++ > 5) break; /* too many subjects makes things real sluggish */

		var ss = arr[sub];

		/* only taking first part of subject (non-topic, etc.) */
		if( ss.constructor == Array)
			ss = ss[0];

		if( ss.constructor != Array )
			ss = [ss];

		for( var i in ss ) {
			var s = normalize(ss[i]);
			this.subjectBox.addItem( this.mkSubjectLink(s), s );
		}
	}

	var series = record.series();
	for( var s in  series ) {
		debug("Found series entry: " + series[s] );
		var ss = normalize(series[s]);
		this.seriesBox.addItem( this.mkSeriesLink(ss), ss );
	}

	/* requestBatch will only have one request in it when the current
		record is the last record requested */
	if( this.requestBatch.pending() < 2  )
		this.finalizePage();

	debug("Finished displaying record " + record.doc_id());
}

AbstractRecordResultPage.prototype.mkAuthorLink = function(auth) {
	var href = createAppElement("a");
	add_css_class(href,"record_result_sidebar_link");

	href.setAttribute("href",
		"?target=mr_result&mr_search_type=author&page=0&mr_search_query=" +
		encodeURIComponent(auth) +
		"&mr_search_depth=" + this.searchDepth +
		"&mr_search_location=" + this.searchLocation +
		"&location=" +  this.searchLocation +
		"&depth=" +  this.searchDepth);

	href.appendChild(createAppTextNode(auth));
	href.title = "Author search for " + auth;
	return href;
}

AbstractRecordResultPage.prototype.mkSeriesLink = function(series) {
	var href = createAppElement("a");
	add_css_class(href,"record_result_sidebar_link");

	debug("Series: " + series + " : " + encodeURIComponent(series));

	href.setAttribute("href",
		"?target=mr_result&mr_search_type=series&page=0&mr_search_query=" +
		encodeURIComponent(series) +
		"&mr_search_depth=" + this.searchDepth +
		"&mr_search_location=" + this.searchLocation +
		"&location=" +  this.searchLocation +
		"&depth=" +  this.searchDepth);

	href.appendChild(createAppTextNode(series));
	href.title = "Series search for " + series;
	return href;
}

AbstractRecordResultPage.prototype.mkSubjectLink = function(sub) {
	var href = createAppElement("a");
	add_css_class(href,"record_result_sidebar_link");
	href.setAttribute("href",
		"?target=mr_result&mr_search_type=subject&page=0&mr_search_query=" +
		encodeURIComponent(sub) + 
		"&mr_search_depth=" + this.searchDepth +
		"&mr_search_location=" + this.searchLocation +
		"&location=" +  this.searchLocation +
		"&depth=" +  this.searchDepth);

	href.appendChild(createAppTextNode(sub));
	href.title = "Subject search for " + sub;
	return href;
}

AbstractRecordResultPage.prototype.finalizePage = function() {

	if( this.finalized )
		return;
	this.finalized = true;


	this.subjectBox.finalize();
	this.authorBox.finalize();
	this.seriesBox.finalize();

	this.sidebarBox.appendChild(this.subjectBox.getNode());
	this.sidebarBox.appendChild(createAppElement("br"));

	this.sidebarBox.appendChild(this.authorBox.getNode());
	this.sidebarBox.appendChild(createAppElement("br"));

	this.sidebarBox.appendChild(this.seriesBox.getNode());
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


	if(this.hitCount < 1) {
		if(this.progressBar) this.progressBar.stop();
	}

	/* in case we're hidden */
	showMe(this.bigOlBox);
	showMe(getById("hit_count_cell_2"));

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
				findOrgType(findOrgUnit(
					copy_counts[i].org_unit).ou_type()).opac_label();
		}
		this.theadDrawn = true;
	}

	for( var i in copy_counts) {
		var cell = createAppElement("td");
		add_css_class(cell, "copy_count_cell");
		cell.innerHTML = copy_counts[i].available + " / " + copy_counts[i].count;
		cell.setAttribute("rowspan","3");
		cell.rowSpan = 3;
		cell.title = " Availabie Copies / Total Copies";
		titlerow.appendChild(cell);
	}

	if(page_id  == (parseInt(this.hitsPerPage) - 1) ) {
		if(this.progressBar) this.progressBar.stop();
		if(this.hitCount < 1)
			this.noHits();
	}

	if( (page_id  == ((parseInt(this.hitCount) - 1 ) - parseInt(this.searchOffset))) ||
			(page_id == (parseInt(this.hitsPerPage) - 1) )) 
		if(this.progressBar) this.progressBar.stop();
}



AbstractRecordResultPage.prototype.noHits = function() {
	var hcell = getById("hit_count_cell");
	hcell.appendChild(createAppElement("br"));
	hcell.appendChild(createAppTextNode("0 hits were returned for you search"));
}


AbstractRecordResultPage.prototype.buildNextLinks = function() {

	if(this.builtLinks)
		return;
	this.builtLinks = true;

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
	var hcell2 = getById("hit_count_cell_2");
	hideMe(hcell2);

	var ident = "Titles";
	if(instanceOf(this, MRResultPage))
		ident = "Title Groups";

	hcell.appendChild(
		createAppTextNode( "Displaying " + ident + " " +
		( parseInt(i) + 1 ) + " to " + max + " of " + this.hitCount));

	hcell.appendChild(createAppTextNode(" "));
	hcell.appendChild(createAppTextNode(" "));
	hcell.appendChild(createAppTextNode(" "));

	/*
	var div = createAppElement("div");
	div.appendChild(createAppTextNode("."));
	div.setAttribute("style", "color:#FFF;float:left;width:10px;border:1px solid black;position:relative");
	hcell.appendChild(div);
	*/

	hcell.appendChild(prev);
	var span = createAppElement("span");
	span.appendChild(createAppTextNode(" ... "));
	hcell.appendChild(span);
	hcell.appendChild(next);

	hcell2.innerHTML = hcell.innerHTML;
	
}


AbstractRecordResultPage.prototype.buildResourcePic = function(c, resource) {
	return buildResourcePic(c, resource);
}

function buildResourcePic(c, resource) {

	var pic = createAppElement("img");

	pic.setAttribute("src", "/images/" + resource + ".jpg");
	pic.className = "record_resource_pic";
	pic.setAttribute("width", "20");
	pic.setAttribute("height", "20");
	pic.setAttribute("title", resource);


	var index;

	switch(resource) {

		case "text":
			index = 0;
			break;

		case "moving image":
			index = 1;
			break;

		case "sound recording":
			index = 2;
			break;

		case "software, multimedia":
			index = 3;
			break;

		case "still images":
			index = 4;
			break;

		case "cartographic":
			index = 5;
			break;

		case "mixed material":
			index = 6;
			break;

		case "notated music":
			index = 7;
			break;

		case "three dimensional object":
			index = 8;
			break;

		default:
			index = 0;
	}

	c.childNodes[index].innerHTML = "";
	c.childNodes[index].appendChild(pic);
}

AbstractRecordResultPage.prototype.buildRecordImage = function(pic_cell, record, page_id, title) {

	debug("Building record image for " + page_id);
	var isbn = record.isbn();
	if(isbn) isbn = isbn.replace(/\s+/,"");
	else isbn = "";

	pic_cell.setAttribute("rowspan","3");
	pic_cell.rowSpan = 3;

	pic_cell.noWrap = 'nowrap';
	pic_cell.setAttribute("nowrap", "nowrap");

	pic_cell.width = "60";
	pic_cell.className = "record_image_cell";


	var rankBox;
	if( this.ranks.length > 0 ) {
		var x = (parseInt(this.page) * parseInt(this.hitsPerPage)) + parseInt(page_id);
		var per = parseInt(this.ranks[x] / this.ranks[0] * 100.0);

		debug("Per is " + per);
		per = 100 - parseInt(per);

		rankBox = createAppElement("div");
		add_css_class(rankBox, "relevance_box");

		var d = createAppElement("div");
		d.setAttribute("height", per + "%");
		d.style.height = per + "%";

		add_css_class(d, "relevance");
		rankBox.appendChild(d);

		rankBox.setAttribute("title", parseInt((100 - parseInt(per))) + "% Relevant");
	}

	/* use amazon for now */
	var img_src = "http://images.amazon.com/images/P/" +isbn + ".01.MZZZZZZZ.jpg";
	var big_div = createAppElement("div");
	add_css_class(big_div, "record_image_big hide_me");

	var big_pic = createAppElement("img");
	var pic = createAppElement("img");
	
	big_pic.setAttribute("src", img_src);
	big_pic.setAttribute("border", "0");
	pic.setAttribute("src", img_src);
	add_css_class(big_pic, "record_image");
	add_css_class(pic, "record_image");

	pic.setAttribute("width", "45");
	pic.setAttribute("height", "50");
	pic.style.width = "45";
	pic.style.height = "50";

	if(IE) 
		big_div.style.left = 0;


	var anch = this.mkLink(record.doc_id(), "img", title );
	anch.appendChild(big_pic);
	big_div.appendChild(anch);
	pic_cell.appendChild(big_div);

	pic_cell.appendChild(pic);

	if(rankBox)
		pic_cell.appendChild(rankBox);

	pic.onmouseover = function() {showMe(big_div);}
	big_div.onmouseout = function(){hideMe(big_div);}

}


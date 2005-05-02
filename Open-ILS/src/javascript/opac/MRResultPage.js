var globalMRResultPage = null;					/* our global object */

MRResultPage.prototype					= new AbstractRecordResultPage();
MRResultPage.prototype.constructor	= MRResultPage;
MRResultPage.baseClass					= AbstractRecordResultPage.constructor;

/* constructor for our singleton object */
function MRResultPage() {
	debug("MRResultPage()");
	//this.searchBar = new SearchBarChunk();

	if( globalMRResultPage != null ) {
		debug("MRResultPage() exists, returning");
		return globalMRResultPage;
	}

	//this.progressBar = new ProgressBar(getById('progress_bar'));
	this.resetSearch();
	globalMRResultPage = this;
}


/* returns the global instance. builds the instance if necessary.  All client
 * code should use this method */
MRResultPage.instance = function() {
	if( globalMRResultPage != null ) {
		return globalMRResultPage;
	} 
	return new MRResultPage();
}

MRResultPage.prototype.next = function() {
	url_redirect( [ 
			"target",				"mr_result",
			"mr_search_type",		this.stype,
			"mr_search_query",	this.string,
			"page",					this.page + 1	
			] );
}


MRResultPage.prototype.prev = function() {
	if(this.page == 0 ) return;
	url_redirect( [ 
			"target",				"mr_result",
			"mr_search_type",		this.stype,
			"mr_search_query",	this.string,
			"page",					this.page - 1	
			] );
}


MRResultPage.prototype.addMenuItems = function(menu, record) {
		menu.addItem("View Metarecord Details", 
							function() { alert(record.doc_id()); });
				xulEvtMRResultDisplayed( menu, record );
}


MRResultPage.prototype.mkLink = function(id, type, value) {

	var href;

	switch(type) {

		case "title":
			href = createAppElement("a");
			add_css_class(href,"record_result_title_link");
			href.setAttribute("href","?target=record_result&page=0&mrid=" + id );
			href.appendChild(createAppTextNode(value));
			break;

		case "author":
			href = createAppElement("a");
			add_css_class(href,"record_result_author_link");
			href.setAttribute("href","?target=mr_result&mr_search_type=author&page=0&mr_search_query=" +
					      encodeURIComponent(value));
			href.appendChild(createAppTextNode(value));
			break;

		default:
			throw new EXArg("Unknown link type: " + type );
	}

	return href;
}



/* performs a new search */
MRResultPage.prototype.doSearch = function() {


	var string			= paramObj.__mr_search_query;
	var stype			= paramObj.__mr_search_type;
	if(!stype || !string) return;

	var orgunit;
	if(globalSelectedLocation) 
		orgunit = globalSelectedLocation;
	else orgunit = globalLocation;

	if(this.searchDepth == null)
		this.searchDepth = globalSearchDepth;

	debug("Current search depth: " + globalSearchDepth);
	debug("My search depth: " + this.searchDepth);

	/* see if this is a new search */
	if(	string != this.string				|| 
			stype != this.stype					||
			this.searchLocation != orgunit	||
			this.searchDepth != globalSearchDepth ) {

		this.resetSearch();
		this.searchDepth = globalSearchDepth;
	}

	this.searchLocation	= orgunit;
	this.stype				= stype;
	this.string				= string;
	this.page				= parseInt(paramObj.__page);
	this.searchOffset		= this.page * this.hitsPerPage;


	//this.progressBar.progressStart();

	this.resetPage();

	var offset = parseInt(this.searchOffset);
	var hitspp	= parseInt(this.hitsPerPage);

	/* is this just a call to next/prev? */
	if( this.recordIDs && this.recordIDs[offset] != null )  {
		debug("We have the first part of the ID's");
		if( this.recordIDs[offset + (hitspp -1 )] != null  ||
				this.recordIDs[this.hitCount - 1] != null ) {
			/* we already have all of the IDS */
			debug("We alread have the required mr " + 
					"ids for the search: [" + this.string + "]");
			this.collectRecords();
			return;
		}
	}


	debug("MRResultPage doSearch() with type: " 
			+ this.stype + " and search [" + this.string + "]"
			+ " and offset " + this.searchOffset );



	var request = new RemoteRequest( 
			"open-ils.search", "open-ils.search.biblio.class", 
			this.stype, this.string, 
			this.searchLocation.id(), 
			this.searchDepth, "50", this.searchOffset );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			try {
				var result = req.getResultObject();
				debug( "MRSearch returned: " + js2JSON(result) );
				obj.gatherIDs(result) 
				obj.collectRecords();
			} catch(E) { throw ("Search Error " + E ); }
		}
	);

	request.send();
}


MRResultPage.prototype.collectRecords = function() {

	var i = this.searchOffset;

	var hcell = getById("hit_count_cell");
	hcell.innerHTML = "Hits";
	hcell.innerHTML += "&nbsp;&nbsp;";
	hcell.innerHTML += this.hitCount;

	while( i < (this.searchOffset + this.hitsPerPage) ) {
		var id = this.recordIDs[i];

		if(id==null){ i++;  continue; }

		var request = new RemoteRequest( "open-ils.search",
			"open-ils.search.biblio.metarecord.mods_slim.retrieve", id );
		this.requestBatch.push(request);

		request.name = "record_request_" + i;
		request.search_id = i;
		request.page_id	= parseInt(i) - parseInt(this.searchOffset);

		debug("Collecting metarecord for id " + id + " and search_id " + i);


		/* define the callback for when we receive the record */
		var obj = this;
		request.setCompleteCallback(
			function(req) {
				//try {
					var record = req.getResultObject();
					obj.displayRecord( record, req.search_id, req.page_id );
					obj.doCopyCount( record, req.search_id, req.page_id );
				//} catch(E) { 
				//	alert("Doc Retrieval Error:\n" + E); 
				//}
			}
		);

		request.send();
		i++;
	}
}

MRResultPage.prototype.doCopyCount = function( record, search_id, page_id ) {

	var copy_box	= getById("record_result_copy_count_box_" + page_id );

	/* kick off the copy count search */
	debug("Grabbing copy count for record " + record.doc_id() );
	var copy_request = new RemoteRequest( "open-ils.search",
		"open-ils.search.biblio.metarecord.copy_count", 1, record.doc_id() );
	this.requestBatch.push(copy_request);

	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	debug("Sending copy request " + search_id + ":" + record.doc_id() );

	var obj = this;
	copy_request.setCompleteCallback( 
		function(req) {
			try {	
				copy_box.innerHTML = req.getResultObject();	
			} catch(E) { 
				//alert("Copy Count Retrieval Error:\n" + E ); 
			}
		}
	);

	copy_request.send();
}



MRResultPage.prototype.doCopyCount = function( record, search_id, page_id ) {

	var copy_box	= getById("record_result_copy_count_box_" + page_id );

	/* kick off the copy count search */
	var orgunit = globalSelectedLocation;
	if(!orgunit) orgunit = globalLocation;

	var copy_request = new RemoteRequest( "open-ils.search",
		"open-ils.search.biblio.metarecord.copy_count",
		orgunit.id(), record.doc_id() );

	this.requestBatch.push(copy_request);

	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	debug("Sending copy request " + search_id + ":" + record.doc_id() );

	var obj = this;
	copy_request.setCompleteCallback( 
		function(req) {
			try {	
				obj.displayCopyCounts(req.getResultObject(), search_id, page_id );
			} catch(E) { 
				//alert("Copy Count Retrieval Error:\n" + E ); 
			}
		}
	);

	copy_request.send();
}


/*
MRResultPage.prototype.gatherIDs = function(result) {

	this.hitCount = parseInt(result.count);
	debug("here");

	for( var i in result.ids ) {
		if(result.ids[i]==null || result.ids[i][0] == null) break;
		var offset = parseInt(i) + parseInt(this.searchOffset);
		this.recordIDs[offset] = result.ids[i][0];
		this.ranks[offset] = parseFloat(result.ids[i][1]);
		debug("adding ranks[" + offset + "] = " + result.ids[i][1] + 
				"  \nrecordIDs["+offset+"], result.ids["+i+"][0]");
	}

}
*/



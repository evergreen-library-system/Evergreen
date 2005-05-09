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

	var location = globalSelectedLocation;
	if(location == null) 
		location = globalLocation.id();
	else
		location = location.id();

	/* if the user has changed the 'location' of the search, it will be
		reflected when the user hits the next button.  the search depth
		will not change, however, because that is a different search */
	url_redirect( [ 
			"target",					"mr_result",
			"mr_search_type",			this.stype,
			"mr_search_query",		this.string,
			"mr_search_location",	location,
			"mr_search_depth",		this.searchDepth,
			"page",						this.page + 1	
			] );
}


MRResultPage.prototype.prev = function() {
	if(this.page == 0 ) return;


	var depth = globalSearchDepth;
	var location = globalSelectedLocation;
	if(location == null) 
		location = globalLocation.id();
	else
		location = location.id();

	/* if the user has changed the 'location' of the search, it will be
		reflected when the user hits this  button.  the search depth
		will not change, however, because that is a different search */
	url_redirect( [ 
			"target",					"mr_result",
			"mr_search_type",			this.stype,
			"mr_search_query",		this.string,
			"mr_search_location",	location,
			"mr_search_depth",		this.searchDepth,
			"page",						this.page - 1	
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
	var location		= paramObj.__mr_search_location;
	var depth			= paramObj.__mr_search_depth;

	debug("mr search params string " + string + " stype " + stype +
			" location " + location + " depth " + depth );

	if(depth == null)
		depth = globalSearchDepth;
	if(location == null)
		location = globalLocation.id();

	if(!stype || !string) return;

	if(this.searchDepth == null)
		this.searchDepth = globalSearchDepth;

	/* see if this is a new search */
	if(	string != this.string				|| 
			stype != this.stype					||
			this.searchLocation != location	||
			this.searchDepth != depth ) {
		this.resetSearch();
	}

	this.searchDepth		= depth;
	this.searchLocation	= location;
	this.stype				= stype;
	this.string				= string;
	this.page				= parseInt(paramObj.__page);
	this.searchOffset		= this.page * this.hitsPerPage;

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
			+ " and offset " + this.searchOffset  +
			" depth: " + depth + " location: " + location);



	var request = new RemoteRequest( 
			"open-ils.search", "open-ils.search.biblio.class", 
			this.stype, this.string, 
			this.searchLocation, 
			this.searchDepth, "50", this.searchOffset );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			var result = req.getResultObject();
			obj.gatherIDs(result) 
			obj.collectRecords();
			obj.requestBatch.remove(req);
		}
	);

	this.requestBatch.add(request);
	request.send();
}


MRResultPage.prototype.collectRecords = function() {

	
	var i = this.searchOffset;

	while( i < (this.searchOffset + this.hitsPerPage) ) {
		var id = this.recordIDs[i];

		if(id==null){ i++;  continue; }

		var request = new RemoteRequest( "open-ils.search",
			"open-ils.search.biblio.metarecord.mods_slim.retrieve", id );
		this.requestBatch.add(request);
		debug( "Sending mods retrieval for metarecord " + id );

		request.name = "record_request_" + i;
		request.search_id = i;
		request.page_id	= parseInt(i) - parseInt(this.searchOffset);

		/* define the callback for when we receive the record */
		var obj = this;
		request.setCompleteCallback(
			function(req) {
				var record = req.getResultObject();
				obj.displayRecord( record, req.search_id, req.page_id );
				obj.doCopyCount( record, req.search_id, req.page_id );
				obj.requestBatch.remove(req);
			}
		);

		request.send();
		i++;
	}
}



MRResultPage.prototype.doCopyCount = function( record, search_id, page_id ) {

	var copy_box	= getById("record_result_copy_count_box_" + page_id );

	var orgunit = globalSelectedLocation;
	if(!orgunit) orgunit = globalLocation;

	var copy_request = new RemoteRequest( 
		"open-ils.search",
		"open-ils.search.biblio.metarecord.copy_count",
		this.searchLocation, record.doc_id() );

	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	var obj = this;
	copy_request.setCompleteCallback( 
		function(req) {
			try {	
				obj.displayCopyCounts(req.getResultObject(), search_id, page_id );
			} catch(E) { 
				debug("****** Copy Count Retrieval Error:\n" + E ); 
			}
		}
	);

	copy_request.send();
}



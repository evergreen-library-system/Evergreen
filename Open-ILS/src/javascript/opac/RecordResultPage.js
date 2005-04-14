var globalRecordResultPage = null;					/* our global object */

RecordResultPage.prototype					= new AbstractRecordResultPage();
RecordResultPage.prototype.constructor	= RecordResultPage;
RecordResultPage.baseClass					= AbstractRecordResultPage.constructor;

/* constructor for our singleton object */
function RecordResultPage() {

	debug("in RecordResultPage()");

	if( globalRecordResultPage != null ) {
		debug("globalRecordResultPage already exists: " + 
				globalRecordResultPage.toString() );
		return globalRecordResultPage;
	}
	globalRecordResultPage = this;
	this.resetSearch();
	debug("Built a new RecordResultPage()");
}


/* returns the global instance. builds the instance if necessary.  All client
 * code should use this method */
RecordResultPage.instance = function() {
	if( globalRecordResultPage != null ) {
		return globalRecordResultPage;
	} 
	return new RecordResultPage();
}

RecordResultPage.prototype.next = function() {
	paramObj.__page = parseInt(paramObj.__page) + 1;
	var paramArray = build_param_array();
	url_redirect( paramArray ) 
}


RecordResultPage.prototype.prev = function() {
	paramObj.__page = parseInt(paramObj.__page) - 1;
	var paramArray = build_param_array();
	url_redirect( paramArray ) 
}


RecordResultPage.prototype.mkLink = function(id, type, value) {

	var href;

	switch(type) {

		case "title":
			href = document.createElement("a");
			add_css_class(href,"record_result_title_link");
			href.setAttribute("href","?target=record_result&mrid=" + id );
			href.appendChild(document.createTextNode(value));
			break;

		case "author":
			href = document.createElement("a");
			add_css_class(href,"record_result_author_link");
			href.setAttribute("href","?target=mr_result&mr_search_type=author&mr_search_query=" +
					      encodeURIComponent(value));
			href.appendChild(document.createTextNode(value));
			break;

		default:
			throw new EXArg("Unknown link type: " + type );
	}

	return href;

}

RecordResultPage.prototype.toString = function() {

	return "\nRecordResultPage:\n"	+
		"page: "						+ this.page + "\n" +
		"searchOffset: "			+ this.searchOffset + "\n" +
		"recordIDs: "				+ this.recordIDs + "\n" +
		"hitCount: "				+ this.hitCount + "\n" +
		"hitsPerPage: "			+ this.hitsPerPage + "\n";

}


RecordResultPage.prototype.isNewSearch = function() {
	if(this.page == 0)
		return true;
	return false;

}

/* performs a new search */
RecordResultPage.prototype.doSearch = function() {

	debug( "Key Value Array \n" + js2JSON( paramObj ) );

	this.page			= parseInt(paramObj.__page);
	this.searchOffset = this.page * this.hitsPerPage;


	if(this.isNewSearch()) {
		debug("RecordResultPage resetting search..");
		this.resetSearch();
	}

	/* is is just a call to next/prev? */
	if( this.recordIDs && this.recordIDs[this.searchOffset] != null &&
		this.recordIDs[this.searchOffset + this.hitsPerPage] != null ) {
		/* we already have all of the IDS */
		debug("We alread have the required mr ids for the search: [" + this.string + "]");
		this.collectRecords();
		return;
	}


	if( paramObj.__mrid != null ) {
		this.mrSearch(paramObj.__mrid);
		return;
	}

	if( paramObj.__search == "global" ) {

		if( paramObj.__tcn != null ) {
			this.globalSearch("tcn", paramObj.__tcn);
			return;
		}

		if( paramObj.__isbn != null ) {
			this.globalSearch("isbn", paramObj.__isbn);
			return;
		}
	}
		
}


/* these are the simple global searches */
RecordResultPage.prototype.globalSearch = function(type, term) {

	if( !term || term.length < 2 )
		throw new EXArg( "globalSearch needs valid term: " + term );

	debug("Performing Global search for term: " + term );

	var method;
	switch( type ) {
		case "tcn":
			method = "open-ils.search.biblio.tcn";
			break;

		case "isbn":
			method = "open-ils.search.biblio.isbn";
			break;
	}

	var request = new RemoteRequest( "open-ils.search",  method, term );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			try {
				var result = req.getResultObject();
				debug( "Global Search returned: " + js2JSON(result) );
				obj.gatherIDs(result) 
				obj.collectRecords();
			} catch(E) { throw ("Search Error " + E ); }
		}
	);
	request.send();
}


RecordResultPage.prototype.mrSearch = function(mrid) {

	var request = new RemoteRequest("open-ils.search",
		"open-ils.search.biblio.metarecord_to_records", mrid );
	debug("Gathering doc ids for metarecord " + mrid );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			try{
				obj.gatherIDs(req.getResultObject());
				obj.collectRecords();
			} catch(E) { throw ("Search Error " + E ); }
		}
	);
	request.send();
}

RecordResultPage.prototype.collectRecords = function() {

	var i = this.searchOffset;

	var hit_box = getById("hit_count_count_box");
	debug("Adding Hit Count: " + this.hitCount );
	hit_box.appendChild(
		document.createTextNode(parseInt(this.hitCount)));

	while( i < (this.searchOffset + this.hitsPerPage) ) {
		var id = this.recordIDs[i];

		if(id==null){ i++;  continue; }

		var request = new RemoteRequest( "open-ils.search",
			"open-ils.search.biblio.record.mods_slim.retrieve", id );
		this.requestBatch.push(request);

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
			}
		);

		request.send();
		i++;
	}
}

RecordResultPage.prototype.doCopyCount = function( record, search_id, page_id ) {

	var copy_box	= getById("record_result_copy_count_box_" + page_id );

	/* kick off the copy count search */
	var copy_request = new RemoteRequest( "open-ils.search",
		"open-ils.search.biblio.record.copy_count", 1, record.doc_id );
	this.requestBatch.push(copy_request);

	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	debug("Sending copy request " + search_id + ":" + record.doc_id );

	var obj = this;
	copy_request.setCompleteCallback( 
		function(req) {
			try {	
				//copy_box.innerHTML = req.getResultObject();	
				copy_box.appendChild(
					document.createTextNode(req.getResultObject()));	
			} catch(E) { 
				alert("Copy Count Retrieval Error:\n" + E ); 
			}
		}
	);

	copy_request.send();
}




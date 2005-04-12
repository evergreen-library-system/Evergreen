var globalRecordResultPage = null;					/* our global object */

RecordResultPage.prototype					= new AbstractRecordResultPage();
RecordResultPage.prototype.constructor	= RecordResultPage;
RecordResultPage.baseClass					= AbstractRecordResultPage.constructor;

/* constructor for our singleton object */
function RecordResultPage() {
	if( globalRecordResultPage != null ) 
		return globalRecordResultPage;

	this.searchBarForm = new SearchBarFormChunk();
	this.init();
	globalRecordResultPage = this;
}


/* returns the global instance. builds the instance if necessary.  All client
 * code should use this method */
RecordResultPage.instance = function() {
	if( globalRecordResultPage != null ) {
		return globalRecordResultPage;
	} 
	return new RecordResultPage();
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

	debug("Returning HREF for link: " + href );

	return href;

}



/* performs a new search */
RecordResultPage.prototype.doSearch = function() {

	debug( "Key Value Array \n" + js2JSON( paramObj ) );

	this.reset();

	if( paramObj.mrid != null ) {
		this.mrSearch(paramObj.mrid);
		return;
	}

	if( paramObj.search == "global" ) {

		if( paramObj.tcn != null ) {
			this.globalSearch("tcn", paramObj.tcn);
			return;
		}

		if( paramObj.isbn != null ) {
			this.globalSearch("isbn", paramObj.isbn);
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

	while( i < (this.searchOffset + this.hitsPerPage) ) {
		var id = this.recordIDs[i];

		if(id==null){ i++;  continue; }

		var request = new RemoteRequest( "open-ils.search",
			"open-ils.search.biblio.record.mods_slim.retrieve", id );
		this.requestBatch.push(request);

		request.name = "record_request_" + i;
		request.search_id = i;
		request.page_id	= parseInt(i) - parseInt(this.searchOffset);

		var hit_box = document.getElementById("hit_count_count_box");
		//hit_box.innerHTML = this.hitCount;
		hit_box.appendChild(
				document.createTextNode(this.hitCount));

		/* define the callback for when we receive the record */
		var obj = this;
		request.setCompleteCallback(
			function(req) {
			//	try {
					var record = req.getResultObject();
					obj.displayRecord( record, req.search_id, req.page_id );
					obj.doCopyCount( record, req.search_id, req.page_id );
			//	} catch(E) { 
					//alert("Doc Retrieval Error:\n" + E); 
			//		debug(" !!! Doc Retrieval Error:\n" + E); 
		//		}
			}
		);

		request.send();
		i++;
	}
}

RecordResultPage.prototype.doCopyCount = function( record, search_id, page_id ) {

	var copy_box	= document.getElementById("record_result_copy_count_box_" + page_id );

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




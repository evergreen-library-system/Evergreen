var globalMRResultPage = null;					/* our global object */

MRResultPage.prototype					= new AbstractRecordResultPage();
MRResultPage.prototype.constructor	= MRResultPage;
MRResultPage.baseClass					= AbstractRecordResultPage.constructor;

/* constructor for our singleton object */
function MRResultPage() {
	if( globalMRResultPage != null ) 
		return globalMRResultPage;

	this.searchBarForm = new SearchBarFormChunk();
	this.init();
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

MRResultPage.prototype.mkLink = function(id, type, value) {

	var href;

	//value = value.replace( /\s+/g,"&nbsp;" );

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
MRResultPage.prototype.doSearch = function(search_continue) {

	//open-ils.search.biblio.class class, term, 
	this.reset();
	if(!search_continue)
		this.resetSearch();

	debug("MRResultPage doSearch() with type: " 
			+ this.stype + " and search [" + this.string + "]"
			+ " and offset " + this.searchOffset );

	var request = new RemoteRequest( 
			"open-ils.search", 
			"open-ils.search.biblio.class", 
			this.stype, this.string, "1", "0", "100", this.searchOffset );

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

		var hit_box = document.getElementById("hit_count_count_box");
		hit_box.innerHTML = this.hitCount;

		/* define the callback for when we receive the record */
		var obj = this;
		request.setCompleteCallback(
			function(req) {
				//try {
					var record = req.getResultObject();
					obj.displayRecord( record, req.search_id, req.page_id );
					/*obj.doCopyCount( record, req.search_id, req.page_id ); */
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

	var copy_box	= document.getElementById("record_result_copy_count_box_" + page_id );

	/* kick off the copy count search */
	var copy_request = new RemoteRequest( "open-ils.search",
		"open-ils.search.biblio.metarecord.copy_count", 1, record.doc_id );
	this.requestBatch.push(copy_request);

	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	debug("Sending copy request " + search_id + ":" + record.doc_id );

	var obj = this;
	copy_request.setCompleteCallback( 
		function(req) {
			try {	
				copy_box.innerHTML = req.getResultObject();	
			} catch(E) { 
				alert("Copy Count Retrieval Error:\n" + E ); 
			}
		}
	);

	copy_request.send();
}




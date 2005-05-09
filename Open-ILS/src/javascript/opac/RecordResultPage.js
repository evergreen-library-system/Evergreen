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

RecordResultPage.prototype.addMenuItems = function(menu, record) {

	var func = function() {
		var req = new RemoteRequest(
				"open-ils.search", 
				"open-ils.search.biblio.record.html",
				record.doc_id());
		req.send(true);
		buildViewMARCWindow(req.getResultObject(), record.doc_id() );
	}

	menu.addItem("View MARC", func);
	xulEvtRecordResultDisplayed( menu, record );

}


function buildViewMARCWindow(html, id) {
	var win = window.open(null,"MARC_" + id,
		"location=0,menubar=0,status=0,resizeable,resize," +
		"outerHeight=500,outerWidth=400,height=500," +
		"width=400,scrollbars=1,screenX=100," +
		"screenY=100,top=100,left=100,alwaysraised" )
	win.document.write(html);
	win.document.close();
	win.document.title = "View MARC";
	win.focus();

}


RecordResultPage.prototype.mkLink = function(id, type, value) {

	var href;

	switch(type) {

		case "title":
			href = createAppElement("a");
			add_css_class(href,"record_result_title_link");
			href.setAttribute("href","?target=record_detail&record=" + id );
			href.appendChild(createAppTextNode(value));
			break;

		case "author":
			href = createAppElement("a");
			add_css_class(href,"record_result_author_link");
			href.setAttribute("href","?target=mr_result&mr_search_type=author&mr_search_query=" +
					      encodeURIComponent(value));
			href.appendChild(createAppTextNode(value));
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
		if( paramObj.__barcode != null ) {
			this.globalSearch("barcode", paramObj.__barcode);
			return;
		}

	}
		
}


/* these are the simple global searches */
RecordResultPage.prototype.globalSearch = function(type, term) {

	if( !term || term.length < 2 )
		throw new EXArg( "globalSearch needs valid term: " + term );

	debug("Performing Global search [" + type + "] for term: " + term );

	var method;
	switch( type ) {
		case "tcn":
			method = "open-ils.search.biblio.tcn";
			break;

		case "isbn":
			method = "open-ils.search.biblio.isbn";
			break;

		case "barcode":
			method = "open-ils.search.biblio.find_by_barcode";
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
	var orgunit = globalSelectedLocation;
	if(!orgunit) orgunit = globalLocation;

	var copy_request = new RemoteRequest( "open-ils.search",
		"open-ils.search.biblio.record.copy_count", 
		orgunit.id(), record.doc_id() );


	copy_request.search_id = search_id;
	copy_request.name = "copy_request_" + (search_id+this.searchOffset);

	debug("Sending copy request " + search_id + ":" + record.doc_id() );

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





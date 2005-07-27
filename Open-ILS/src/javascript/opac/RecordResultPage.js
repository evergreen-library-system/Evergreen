var globalRecordResultPage = null;					/* our global object */

RecordResultPage.prototype					= new AbstractRecordResultPage();
RecordResultPage.prototype.constructor	= RecordResultPage;
RecordResultPage.baseClass					= AbstractRecordResultPage.constructor;

/* constructor for our singleton object */
function RecordResultPage() {

	debug("in RecordResultPage()");

	var row = getById("hourglass_row");
	if(row)
		row.parentNode.removeChild(row);

	if( globalRecordResultPage != null ) {
		debug("globalRecordResultPage already exists: " + 
				globalRecordResultPage.toString() );
		return globalRecordResultPage;
	}
	globalRecordResultPage = this;
	this.resetSearch();
	debug("Built a new RecordResultPage()");

	var row = getById("hourglass_row");
	if(row)
		row.parentNode.removeChild(row);
}


RecordResultPage.buildExtendedLinks = function(record, page_id) {
	return null;
}

RecordResultPage.prototype.setPageTrail = function() {
	var box = getById("page_trail");
	if(!box) return;

	var d = this.buildTrailLink("start", true);
	if(d) {
		box.appendChild(d);
	} else {
		d = this.buildTrailLink("advanced_search", true);
		if(d)
			box.appendChild(d);
	}

	var b = this.buildTrailLink("mr_result", true);

	if(b) {
		box.appendChild(this.buildDivider());
		box.appendChild(b);
	}

	box.appendChild(this.buildDivider());
	box.appendChild(
		this.buildTrailLink("record_result",false));
}





/* returns the global instance. builds the instance if necessary.  All client
 * code should use this method */
RecordResultPage.instance = function() {

	var row = getById("hourglass_row");
	if(row)
		row.parentNode.removeChild(row);

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



RecordResultPage.prototype.URLRefresh = function() {
	paramObj.__page = 0;
	return build_param_array();
}



RecordResultPage.prototype.prev = function() {
	paramObj.__page = parseInt(paramObj.__page) - 1;
	var paramArray = build_param_array();
	url_redirect( paramArray ) 
}


RecordResultPage.prototype.addMenuItems = function(menu, record) {

	var func = buildViewMARCWindow(record);
	menu.addItem("View MARC", func);
	if(isXUL())
		xulEvtRecordResultDisplayed( menu, record );
}


function buildViewMARCWindow(record) {

	debug("Setting up view marc with record " + record.doc_id());
	var func = function() {
		var req = new RemoteRequest(
				"open-ils.search", 
				"open-ils.search.biblio.record.html",
				record.doc_id());
		req.send(true);

		var html = req.getResultObject();
		var id = record.doc_id();

		//var win = window.open(null,"MARC_" + id,
		var win = window.open("about:blank","MARC_" + id,
			"location=0,menubar=0,status=0,resizeable,resize," +
			"outerHeight=500,outerWidth=400,height=500," +
			"width=400,scrollbars=1,screenX=100," +
			"screenY=100,top=100,left=100,alwaysraised,chrome" )

		win.document.write(html);
		win.document.close();
		win.document.title = "View MARC";
		win.focus();
	}
	
	return func;
}


RecordResultPage.prototype.mkLink = function(id, type, value) {

	var href;

	var org = globalSelectedLocation;
	if(org == null)
		org = globalLocation;

	switch(type) {


		case "title":
			href = createAppElement("a");
			add_css_class(href,"record_result_title_link");
			href.setAttribute("href",
				"?target=record_detail&record=" + id  +
				"&location=" + org.id() +
				"&depth=" + globalSearchDepth );
			href.appendChild(createAppTextNode(value));
			href.title = "View title details for " + value;
			break;

		case "author":
			href = createAppElement("a");
			add_css_class(href,"record_result_author_link");
			href.setAttribute("href","?target=mr_result&mr_search_type=author&page=0&mr_search_query=" +
					      encodeURIComponent(value));
			href.appendChild(createAppTextNode(value));
			href.title = "Author search for " + value + "";
			break;

	case "img":
			href = createAppElement("a");
			add_css_class(href,"record_result_image_link");
			href.setAttribute("href",
					"?target=record_detail&page=0&record=" + id  +
				"&location=" + org.id() +
				"&depth=" + globalSearchDepth );
			href.title = "View title details for " + value;
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

	if(recordResultRedirect) { 
		/* if the user is just hitting the 'back' button */
		recordResultRedirect = false;
		history.go(-1);
		return;
	}

	debug( "Key Value Array \n" + js2JSON( paramObj ) );

	this.page			= parseInt(paramObj.__page);
	var hitsper			= paramObj.__hits_per_page;
	this.format			= paramObj.__format;
	if(!this.format) this.format = "all";

	if(hitsper)
		this.hitsPerPage = parseInt(hitsper);

	debug("******* Hits per = " + this.hitsPerPage);

	this.hitsPerPageSelector = getById('hits_per_page');
	for( var i in this.hitsPerPageSelector.options ) {
		var hits_obj = this.hitsPerPageSelector.options[i];
		if(hits_obj == null) continue;
		var hits = hits_obj.value;
		debug(hits);
		if( this.hitsPerPage == parseInt(hits) ) {
			this.hitsPerPageSelector.options[i].selected = true;
			debug("Setting selected on selector with hits " + hits);
		}
	}

	if(this.page == null)
		this.page = 0;

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

	var request;
	var method = "open-ils.search.biblio.metarecord_to_records";
	if(isXUL()) method += ".staff";

	if(this.format == "all")
		request = new RemoteRequest("open-ils.search", method, mrid );
	else
		request = new RemoteRequest("open-ils.search", method, mrid, this.format );

	debug("Gathering doc ids for metarecord " + mrid );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			try{
				var ids = req.getResultObject();
				obj.gatherIDs(ids);

				if(!recordResultRedirect) { /* if the user isn't just hitting the 'back' button */
					if(parseInt(obj.hitCount) == 1) {
						recordResultRedirect = true;
						debug("Redirecting to record detail page with record " + obj.recordIDs[0] );
					url_redirect( [
							"goto",		"-2",
							"target", "record_detail",
							"record", obj.recordIDs[0] ] );
						return;
					}
				} else { 
					recordResultRedirect = false;
					history.go(-1);
				}

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





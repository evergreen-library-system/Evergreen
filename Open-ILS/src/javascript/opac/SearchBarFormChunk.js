/*  */

var globalSearchBarFormChunk = null;

function SearchBarFormChunk() {
	this.init();
	globalSearchBarFormChunk = this;
}


SearchBarFormChunk.prototype.init = function() {
	debug("Initing searchBarFormchunk");
	this.search_query			= getById("mr_search_query");
	this.search_type			= getById("mr_search_type");
	this.search_button		= getById("mr_search_button");
	this.searchRange			= getById("search_range_select");
}

SearchBarFormChunk.prototype.resetPage = function() {

	this.init();

	this.search_button.onclick		= mrSearchSubmitForm;
	this.search_query.onkeydown	= mrSearchSubmitOnEnter;
	this.search_type.onkeydown		= mrSearchSubmitOnEnter;


	var s = paramObj.__mr_search_query;
	if(!s) s = lastSearchString;
	var t = paramObj.__mr_search_type;
	if(!t) t = lastSearchType;
	if(s) this.search_query.value = s;
	if(t) this.search_type.value = t;

	try{ this.search_query.focus(); } catch(E) {}

//	this.resetRange();

}


	
function mrSearchSubmitForm() {
	var search_query		= getById("mr_search_query").value;
	var search_type		= getById("mr_search_type").value;


	var depth = globalSearchDepth;
	var location = globalSelectedLocation;
	if(location == null) 
		location = globalLocation.id();
	else
		location = location.id();

	url_redirect( [ 
			"target",					"mr_result",
			"mr_search_type",			search_type,
			"mr_search_query",		search_query,
			"mr_search_location",	location,
			"mr_search_depth",		depth,
			"page",						0
			] );
}


/* forces the submission of the search */
function mrSearchSubmitOnEnter(evt) {
	evt = (evt) ? evt : ((window.event) ? event : null); /* for mozilla and IE */
	var obj = globalSearchBarFormChunk;
	var code = grabCharCode(evt); 
	if(code==13||code==3) { 
		mrSearchSubmitForm();
	}
}




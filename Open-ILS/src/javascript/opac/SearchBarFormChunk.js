/*  */

var globalSearchBarFormChunk = null;

function SearchBarFormChunk() {
	this.init();
	this.resetPage();
	globalSearchBarFormChunk = this;
}


SearchBarFormChunk.prototype.init = function() {
	debug("Initing searchBarFormchunk");
	this.search_query			= getById("mr_search_query");
	this.search_type			= getById("mr_search_type");
	this.search_button		= getById("mr_search_button");
}

SearchBarFormChunk.prototype.resetPage = function() {

	debug("pageReset on SearchBarFormChunk");
	this.search_button.onclick		= mrSearchSubmitForm;
	this.search_query.onkeydown	= mrSearchSubmitOnEnter;
	this.search_type.onkeydown		= mrSearchSubmitOnEnter;

	if(paramObj.__mr_search_query)
		this.search_query.value = paramObj.__mr_search_query;

	if(paramObj.__mr_search_type)
		this.search_type.value = paramObj.__mr_search_type;

	try{ this.search_query.focus(); } catch(E) {}

}
	
	
function mrSearchSubmitForm() {
	var search_query		= getById("mr_search_query").value;
	var search_type		= getById("mr_search_type").value;

	debug("Submitting MR search via form");

	url_redirect( [ 
			"target",				"mr_result",
			"mr_search_type",		search_type,
			"mr_search_query",	search_query,
			"page",					0
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




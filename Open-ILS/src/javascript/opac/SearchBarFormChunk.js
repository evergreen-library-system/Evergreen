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
	this.setFormat();
}


SearchBarFormChunk.prototype.setFormat = function() {
	var fsel						= getById("mr_search_format");
	var format					= paramObj.__format;
	for( var idx = 0; idx != fsel.options.length; idx++ ) {
		var obj = fsel.options[idx];
		if(obj && obj.value == format) {
			fsel.selectedIndex = idx;
			obj.selected = true;
		}
	}

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
	var form					= getById("mr_search_format").value 

	/*
	var fsel					= getById("mr_search_format");
	var form					= fsel.options[fsel.selectedIndex].value 
	*/


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
			"format",					form,
			"page",						0
			] );
}


/* forces the submission of the search */
function mrSearchSubmitOnEnter(evt) {
	var win = getWindow();
	evt = (evt) ? evt : ((win.event) ? globalAppFrame.event : null); /* for mozilla and IE */
	var obj = globalSearchBarFormChunk;
	var code = grabCharCode(evt); 
	if(code==13 || code==3) { 
		mrSearchSubmitForm();
		return false;
	}
}




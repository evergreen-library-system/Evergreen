/*  */

var globalSearchBarFormChunk = null;

function SearchBarFormChunk() {

	if( globalSearchBarFormChunk != null) {
		return globalSearchBarFormChunk;
	}

	this.search_query			= document.getElementById("mr_search_query");
	this.search_type			= document.getElementById("mr_search_type");
	this.search_button		= document.getElementById("mr_search_button");
	this.js_search_button	= document.getElementById("mr_js_search_button");

	if(paramObj.mr_search_query)
		this.search_query.value = paramObj.mr_search_query;

	if(paramObj.mr_search_type)
		this.search_type.value = paramObj.mr_search_type;

	if(this.search_button)
		this.search_button.onclick		= mrSearchSubmitForm;
	if(this.js_search_button)
		this.js_search_button.onclick		= mrSearchSubmitSearch;

	this.search_query.onkeydown	= mrSearchSubmitOnEnter;
	this.search_type.onkeydown		= mrSearchSubmitOnEnter;

	try{ this.search_query.focus(); } catch(E) {}
	globalSearchBarFormChunk = this;

}
	
	
function mrSearchSubmitForm() {
	var search_query		= document.getElementById("mr_search_query").value;
	var search_type		= document.getElementById("mr_search_type").value;
	location.href="?target=mr_result&mr_search_type=" + 
		search_type + "&mr_search_query=" + encodeURIComponent(search_query); 
}

function mrSearchSubmitSearch() {
	var obj = globalSearchBarFormChunk;
	globalPage.string = obj.search_query.value; 
	globalPage.stype	= obj.search_type.value;
	debug("Performing search " + globalPage.stype + " " + globalPage.string );
	globalPage.doSearch();
}

/* forces the submission of the search */
function mrSearchSubmitOnEnter(evt) {
	evt = (evt) ? evt : ((window.event) ? event : null); /* for mozilla and IE */
	var obj = globalSearchBarFormChunk;
	var code = grabCharCode(evt); 
	if(code==13||code==3) { 
		if(obj.search_button)
			mrSearchSubmitForm();
		else 
			if(obj.js_search_button)
				mrSearchSubmitSearch();
	}
}




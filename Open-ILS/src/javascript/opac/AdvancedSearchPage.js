AdvancedSearchPage.prototype					= new Page();
AdvancedSearchPage.prototype.constructor	= AdvancedSearchPage;
AdvancedSearchPage.baseClass					= Page.constructor;


var globalAdvancedSearchPage = null;

// ---------------------------------------------------------------------------------
// advanced search
// ---------------------------------------------------------------------------------
function AdvancedSearchPage() {

	if(globalAdvancedSearchPage) 
		return globalAdvancedSearchPage;

	this.searchBar = new SearchBarChunk();
	globalAdvancedSearchPage = this;
}


AdvancedSearchPage.prototype.init = function() {
	this.searchBarForm	= new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();

	this.advISBN			= getById("adv_isbn");

	/* global search */
	this.globalSearchButton	= getById("adv_global_search_button");
	this.tcnText				= getById("adv_tcn_text");
	this.ISBNText				= getById("adv_isbn_text");
	this.barcodeText			= getById("adv_barcode_text");
	var refinedButton			= getById("adv_search_refined_submit");

	this.globalSearchButton.onclick = doGlobalSearch;
	refinedButton.onclick = doGlobalSearch;
}

/* resets the page */
AdvancedSearchPage.prototype.reset = function() {
	this.advISBN.focus();
}

AdvancedSearchPage.instance = function() {
	if(globalAdvancedSearchPage) {
		return globalAdvancedSearchPage;
	}
	return new AdvancedSearchPage();
}

function doGlobalSearch() {

	var obj = AdvancedSearchPage.instance();

	if( obj.ISBNText.value != null 
			&& obj.ISBNText.value.length > 1 ) {
		url_redirect( [ "target", "record_result", "page", "0",
				"search", "global", "isbn", obj.ISBNText.value ] );
		/* do isbn search */
	}

	if( obj.tcnText.value != null 
			&& obj.tcnText.value.length > 1 ) {
		url_redirect( [ "target", "record_result", "page", "0", 
				"search", "global", "tcn", obj.tcnText.value ] );
		return;
	}
	if( obj.barcodeText.value != null 
			&& obj.barcodeText.value.length > 1 ) {
		url_redirect( [ "target", "record_result", "page", "0", 
				"search", "global", "barcode", obj.barcodeText.value ] );
		return;
	}

	var allWords = getById("adv_all_words").value;
	var exactWords = getById("adv_exact_words").value;
	var noneWords	= getById("adv_none_words").value;
	var type = getById("adv_search_type").value;
	if(allWords || exactWords || noneWords) {
		var search_string = obj.buildRefinedSearch(allWords, exactWords, noneWords);
		debug("Refined search string is [ " + search_string + " ] and type " + type);

		url_redirect ([ 
				"target",					"mr_result",
				"mr_search_type",			type,
				"mr_search_query",		search_string,
				"page",						0
				]);

	}

}

AdvancedSearchPage.prototype.buildRefinedSearch = 
			function(allWords, exactWords, noneWords) {
	
	var string = "";

	if(allWords) {
		string = allWords;
	}

	if(exactWords) {
		if(exactWords.indexOf('"') > -1) 
			string += " " + exactWords;
		else 
			string += " \"" + exactWords + "\"";
		
	}

	if(noneWords) {
		var words = noneWords.split(" ");
		for(var i in words) 
			string += " -" + words[i];
	}

	return string;
}
		


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

	globalAdvancedSearchPage = this;
}


AdvancedSearchPage.prototype.init = function() {
	this.searchBarForm	= new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();

	this.advISBN			= document.getElementById("adv_isbn");

	/* global search */
	this.globalSearchButton	= document.getElementById("adv_global_search_button");
	this.tcnText				= document.getElementById("adv_tcn_text");
	this.ISBNText				= document.getElementById("adv_isbn_text");
	this.barcodeText			= document.getElementById("adv_barcode_text");

	this.globalSearchButton.onclick = doGlobalSearch;
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
		url_redirect( [ "target", "record_result", 
				"search", "global", "isbn", obj.ISBNText.value ] );
		/* do isbn search */
	}

	if( obj.tcnText.value != null 
			&& obj.tcnText.value.length > 1 ) {
		url_redirect( [ "target", "record_result", 
				"search", "global", "tcn", obj.tcnText.value ] );
		return;
	}
}
		


var globalRecordDetailPage = null;
RecordDetailPage.prototype					= new Page();
RecordDetailPage.prototype.constructor	= RecordDetailPage;
RecordDetailPage.baseClass					= Page.constructor;

function RecordDetailPage() {
	if( globalRecordDetailPage != null )
		return globalRecordDetailPage;
	this.searchBar	= new SearchBarChunk();
}


RecordDetailPage.instance = function() {
	if( globalRecordDetailPage != null )
		return globalRecordDetailPage;
	return new RecordDetailPage();
}

RecordDetailPage.prototype.init = function() {
	debug("Initing RecordDetailPage");
}

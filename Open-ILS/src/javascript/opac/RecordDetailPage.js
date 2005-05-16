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

RecordDetailPage.prototype.setPageTrail = function() {
	var box = getById("page_trail");
	if(!box) return;

	var d = this.buildTrailLink("start",true);
	if(d) {
		box.appendChild(d);
	} else {
		d = this.buildTrailLink("advanced_search",true);
		if(d)
			box.appendChild(d);
	}

	var b = this.buildTrailLink("mr_result", true);

	if(b) {
		box.appendChild(this.buildDivider());
		box.appendChild(b);
	}

	box.appendChild(this.buildDivider());
	box.appendChild(this.buildTrailLink("record_result", true));

	box.appendChild(this.buildDivider());
	box.appendChild(
		this.buildTrailLink("record_detail",false));
}





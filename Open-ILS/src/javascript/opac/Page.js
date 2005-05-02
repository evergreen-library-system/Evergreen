/* Top level page object.  All pages descend from this class */

function Page() {}

Page.prototype.init = function() {
	debug("Falling back to Page.init()");
}

/* override me */
Page.prototype.instance = function() {
	throw new EXAbstract(
			"instance() must be overridden by all Page subclasses");
}


/* XXX move me to the status bar */

Page.prototype.updateSelectedLocation = function(org) {
	var node;
	if( typeof org == 'object' ) node = org;
	else node = getOrgById(org);
	globalSelectedLocation = node;
	this.setLocDisplay();
}


/* tells the user where he is searching */
Page.prototype.setLocDisplay = function(name) {

	this.searchingCell = getById("now_searching_cell");
	this.searchRange	= getById("search_range_select");

	if( this.searchingCell == null ) return;
	var name;
	
	var orgunit;
	if( globalSelectedLocation )
		orgunit = globalSelectedLocation;
	else { orgunit = globalLocation; }

	var arr = orgNodeTrail(orgunit);

	this.searchingCell.innerHTML = "";
	var names = new Array()
	for( var i in arr) 
		names.push(arr[i].name());

	this.searchingCell.innerHTML = 
		"<span class='breadcrumb_label'>" + 
		names.join("</span> / <span class='breadcrumb_label'>") + 
		"</span>";

	if(globalSearchBarFormChunk)
		globalSearchBarFormChunk.resetPage();

}

Page.prototype.updateCurrentLocation = function(org) {
	if( typeof org == 'object' ) node = org;
	else node = getOrgById(orgid);
	globalLocation = node;
	this.setLocDisplay();
}
		




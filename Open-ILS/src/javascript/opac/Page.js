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
	globalSearchDepth = findOrgType(node.ou_type()).depth();
	this.setLocDisplay();
}

Page.prototype.updateCurrentLocation = function(org) {
	if( typeof org == 'object' ) node = org;
	else node = getOrgById(orgid);
	globalLocation = node;
	this.setLocDisplay();
}
	

/* tells the user where he is searching */
Page.prototype.setLocDisplay = function(name) {

	debug("Setting loc display on the status bar");
	this.searchingCell = getById("now_searching_cell");

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

	this.resetRange();

}

Page.prototype.resetRange = function() {

	this.searchRange			= getById("search_range_select");

	while( this.searchRange.options.length ) {
		this.searchRange.options[0] = null;
	}

	var orgunit = globalSelectedLocation;
	if(!orgunit)
		orgunit = globalLocation;

	debug("Reseting search range with search location " + orgunit);
	debug("Resetting search range with search depth " + globalSearchDepth );

	var selectedOption = null;

	if(this.searchRange) {

		for( var index in globalOrgTypes ) {
			var otype = globalOrgTypes[index];

			if( otype.depth() > findOrgType(orgunit.ou_type()).depth() )
				continue;

			var select =  new Option(otype.name(), otype.depth());

			this.searchRange.options[this.searchRange.options.length] = select;

			if( otype.depth() == globalSearchDepth ) {
				selectedOption = index;
			}
		}
	}

	this.searchRange.selectedIndex = selectedOption;
	this.searchRange.options[selectedOption].selected = true;

	if(this.searchRange.options.length == 1 ) 
		hideMe(this.searchRange.parentNode);
	else  {
		this.searchRange.parentNode.style.visibility = "visible";
		this.searchRange.parentNode.style.display = "inline";
	}

	if( instanceOf(this, AbstractRecordResultPage) ) {

		/* submit the search when the search range is selected */
		var obj = this;

		debug("Setting onclick for selector");
		this.searchRange.onchange = function() {
	
			var location = globalSelectedLocation;
			if(location == null) location = globalLocation.id();
			else location = location.id();
			globalSearchDepth = obj.searchRange.options[obj.searchRange.selectedIndex].value;	
	
			url_redirect( [ 
					"target",					"mr_result",
					"mr_search_type",			lastSearchType,
					"mr_search_query",		lastSearchString,
					"mr_search_location",	location,
					"mr_search_depth",		globalSearchDepth,	
					"page",						0
					] );
		}
	}
}





Page.prototype.setPageTrail = function() {
	debug("Falling back to Page.setPageTrail");
}


Page.prototype.buildTrailLink = function(type, active) {

	var obj = locationStack[type];
	if(obj == null) return;

	var div = createAppElement("div");

	if(active) {
		add_css_class(div,"page_trail_word");
		var a = createAppElement("a");
		a.setAttribute("href", obj.location);
		a.appendChild(createAppTextNode(obj.title));
		a.title = obj.title;
		div.appendChild(a);

	} else {
		add_css_class(div,"page_trail_word_inactive");
		div.appendChild(createAppTextNode(obj.title));
	}

	return div;
}

Page.prototype.buildDivider = function() {
	var div = createAppElement("div");
	div.className = "page_trail_divider";
	var text =  createAppTextNode(" / ");
	div.appendChild(text);
	return div;
}


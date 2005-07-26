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

	this.searchingCell.innerHTML = 
		"Now Searching <span class='breadcrumb_label'>" + orgunit.name() + "</span>";

	this.resetRange();
	return;




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

			var select =  new Option(otype.opac_label(), otype.depth());
			this.searchRange.options[this.searchRange.options.length] = select;

			if( otype.depth() == globalSearchDepth ) {
				selectedOption = index;
			}
		}
	}

	this.searchRange.selectedIndex = selectedOption;
	var opt = this.searchRange.options[selectedOption];
	if(opt) opt.selected = true;

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

		var obj = this;
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
					"format",					paramObj.__format, 
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

/* if 'full' add target=_top to break out of the page */
Page.prototype.buildNavBox = function(full) {
	Page.navBox = new Box();
	Page.navBox.init("Navigation", false, false);
	var table = elem("table");
	add_css_class(table, "main_nav_table");

	var arr = [];

	/* location tree */
	var loc = null;
	try {
		if(globalOrgTree)
			loc = elem("a", 
				{id:"location_nav_link", href:"javascript:void(0);"}, 
				null, "Change Search Location");

		loc.onclick = function(evt) {
			globalPage.locationTree.toggle(getById("location_nav_link"));
		}
		arr.push(loc);
	} catch(E){}

	if(globalPort == "443") globalPort = "80";
	var prefix = "http://" + globalRootURL + ":" + globalPort + globalRootPath;

	arr.push(elem("a", {href: prefix + '?target=advanced_search'}, null, "Advanced Search"));


	if(!isXUL()) {
		var mylink = elem("a", {href: "?target=my_opac"}, null, "My OPAC");
		arr.push(mylink);
	}

	/* if user is not logged in, popup the login dialog when they
		select the myopac link */
	if(!UserSession.instance().verifySession()) {
		mylink.setAttribute("href","javascript:void(0);");
		var func = function(){url_redirect(["target","my_opac"])};
		var diag = new LoginDialog(func);
		mylink.onclick = function(){diag.display(mylink);}
	}


	if(loc) arr.push(this.buildDeepLink());

	if(UserSession.instance().verifySession() && !isXUL() ) {
		var a = elem("a", {href:"http://" + globalRootURL + ":" 
				+ globalPort + "/" + globalRootPath}, null, "Logout");
		a.onclick = doLogout;
		arr.push(a);
	} 


	for( var i in arr ) {
		var row = table.insertRow(table.rows.length);
		add_css_class(row, "main_nav_row");
		var cell = row.insertCell(row.cells.length);
		add_css_class(cell, "main_nav_cell");
		cell.appendChild(arr[i]);
		if(full) 
			arr[i].setAttribute("target", "_top");
	}

	/* append to the page */
	Page.navBox.addItem(table);
	Page.navBox.finalize();

	var location = getById("main_page_nav_box");
	if(location) {
		removeChildren(location);
		location.appendChild(Page.navBox.getNode());
	}
	

	return Page.navBox.getNode();
}

Page.prototype.buildDeepLink = function() {
	try {
		if(!globalAppFrame)
			return elem("div");
	} catch(E) { return elem("div"); }

	var org = globalSelectedLocation;
	if(org == null)
		org = globalLocation;
	if(org) org = org.id();

	var depth = globalSearchDepth;

	if(globalPort == "443") globalPort = "80";
	var prefix = "http://" + globalRootURL + ":" + globalPort + globalRootPath;

	var string =globalAppFrame.location.href;
	if(!string.match(/sub_frame/))
		string += "&sub_frame=1"

	if(org) {
		if(!string.match(/location/))
		string += "&location=" + org;
	}

	if(depth) {
		if(!string.match(/depth/))
		string += "&depth=" + depth;
	}

	debug("Redirecting deep link to " + string );

	var a = elem("a",
		{ href: prefix + string }, null, "Link to this page"
	);

	a.setAttribute("target", "_blank");
	return a;
}


Page.prototype.destroy = function() { 
	for( var x in this ){
		this[x] = null;
	}
}









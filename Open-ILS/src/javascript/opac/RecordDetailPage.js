var globalRecordDetailPage = null;
RecordDetailPage.prototype					= new Page();
RecordDetailPage.prototype.constructor	= RecordDetailPage;
RecordDetailPage.baseClass					= Page.constructor;

var globalDetailRecord;

function RecordDetailPage() {
	if( globalRecordDetailPage != null )
		return globalRecordDetailPage;
	this.searchBar	= new SearchBarChunk();
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
	try {
		box.appendChild(this.buildTrailLink("record_result", true));
	} catch(E) {} /* doesn't work when deep linking */

	box.appendChild(this.buildDivider());
	box.appendChild(
		this.buildTrailLink("record_detail",false));
}


RecordDetailPage.instance = function() {
	if( globalRecordDetailPage != null )
		return globalRecordDetailPage;
	return new RecordDetailPage();
}

RecordDetailPage.prototype.init = function() {
	debug("Initing RecordDetailPage");
	this.draw();
}

RecordDetailPage.prototype.draw = function() {

	this.mainBox = getById("record_detail_copy_info");

	this.copyLocationTree = elem("select");
	var opt =  new Option(
		"Select a location whose Volumes/Copies you wish to see");
	this.copyLocationTree.options[this.copyLocationTree.options.length] = opt;
	var tree = this.copyLocationTree;

	var obj = this;

	tree.onchange = function() {

		var idx = tree.selectedIndex;
		debug("INDEX is " + idx);
		var org_id = tree.options[idx].value;	
		if(org_id == null) return;
		obj.drawCopyTrees(findOrgUnit(org_id), obj.record);

		tree.selectedIndex = idx;
		var opt = tree.options[idx];
		if(opt) opt.selected = true;	
		
	}

	var table = elem("table", { width: "100%" } );
	table.width = "100%";

	var linksDiv = table.insertRow(0);
	var leftLink = linksDiv.insertCell(0);
	var rightLink = linksDiv.insertCell(1);

	leftLink.width = "50%";
	rightLink.width = "50%";
	leftLink.align = "left";
	rightLink.align = "right";

	this.parentLink = elem("a",
		{ href : "javascript:void(0)",
			id : "parent_link",
		  style : "text-decoration:underline" } );

	leftLink.appendChild(this.copyLocationTree);
	rightLink.appendChild(this.parentLink);
	this.mainBox.appendChild(table);
	/* --------------------------------------------- */


	this.treeDiv = elem("div");
	this.mainBox.appendChild(this.treeDiv);

	this.fetchRecord(paramObj.__record); /* sets this.record */
	this.viewMarc = getById("record_detail_view_marc");

	this.buildNavBox();
	

}


RecordDetailPage.prototype.buildCustomOrgTree = function(record) {

	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.biblio.copy_counts.retrieve",
		record.doc_id() );

	var obj = this;
	req.setCompleteCallback(
		function(req) {
			_fleshOrgTree(req.getResultObject(), obj.copyLocationTree);}
	);
	debug("Sending copy tree request");
	req.send();
}

/* builds the select list with the appropriate org units */
function _fleshOrgTree(org_array, selector) {

	debug("Fleshing org tree selector");

	for( var idx in org_array ) {
		var slot = org_array[idx];
		var org = findOrgUnit(slot[0]);
		_addOrgAndParents(selector, org);
	}

	debug("Tree is built..");
}


function _addOrgAndParents(selector, org) {

	if(!org || org.added) return;

	debug("Checking org " + org.name());

	if(org.ou_type() == "1") {
		org.added = true;
		return;
	}

	var par = findOrgUnit(org.parent_ou());
	if(par && !par.added)
		_addOrgAndParents(selector, par);


	/* build the selector text part */
	if(IE) {
		var node = elem("pre");
		for(var x=2; x <= findOrgType(org.ou_type()).depth(); x++) {
			node.appendChild(mktext("   "));
		}
		node.appendChild(mktext(org.name()));

		var select = new Option("", org.id());
		selector.options[selector.options.length] = select;
		select.appendChild(node);

	} else {

		var pad = (findOrgType(org.ou_type()).depth() - 1) * 10;
		var select = new Option(org.name(), org.id());
		select.setAttribute("style", "padding-left: " + pad);
		selector.options[selector.options.length] = select;
	}

	org.added = true;
}


function _buildCustomOrgTree(org_node, root) {

	var item;

	if(root) {
		item = new WebFXTree(org_node.name());
		item.setBehavior('classic');
	} else {
		item = new WebFXTreeItem(org_node.name());
	}

	item.action = 
		"javascript:globalPage.drawCopyTrees(" + 
		org_node.id() + ", logicNode.globalDetailRecord );" +
		"globalPage.copyLocationTree.hide();"; 
		
	
	for( var index in org_node.children()) {
		var childorg = org_node.children()[index];
		if( childorg != null ) {
			var tree_node = buildCustomOrgTree(childorg);
			if(tree_node != null)
				item.add(tree_node);
		}
	}

	return item;
}


RecordDetailPage.prototype.setViewMarc = function(record) {
	var marcb = elem( "a", 
		{ 
			href:"javascript:void(0)", 
			style: "text-decoration:underline" 
		}, 
		{}, "View MARC" );

	debug(".ou_type()Setting up view marc callback with record " + record.doc_id());

	var func = buildViewMARCWindow(record);
	marcb.onclick = func;
	this.viewMarc.appendChild(marcb);
}

RecordDetailPage.prototype.setPlaceHold = function(record) {
	var holds = elem( "a", 
		{ 
			href:"javascript:void(0)", 
			style: "text-decoration:underline" 
		}, 
		{}, "Place Hold" );

	var user = UserSession.instance();
	if(!(user && user.verifySession()))  /* needs to pop up a login dialog XXX */
		return;

	var win = new HoldsWindow(record.doc_id(), 
			"T", user.userObject, user.userObject, user.session_id);
	win.buildWindow(); 
	holds.onclick = function() { win.toggle(); }

	var space = elem("span", {style:"padding:5px"},null, " ");
	this.viewMarc.appendChild(space);
	this.viewMarc.appendChild(holds);
}


RecordDetailPage.prototype.fetchRecord = function(id) {
	if(!id) {
		debug("No ID in fetchRecord");
		return;
	}

	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.biblio.record.mods_slim.retrieve",
		id );

	var obj = this;
	req.setCompleteCallback(
		function() { 
			obj.record = req.getResultObject();
			globalDetailRecord = obj.record;
			obj.buildCustomOrgTree(obj.record);
			obj.drawRecord(obj.record); 
			obj.setViewMarc(obj.record);
			obj.setPlaceHold(obj.record);
		} 
	);

	req.send();
}


RecordDetailPage.prototype.drawRecord = function(record) {

	var title_cell			= getById("record_detail_title_cell");
	var author_cell		= getById("record_detail_author_cell");
	var isbn_cell			= getById("record_detail_isbn_cell");

	var edition_cell		= getById("record_detail_edition_cell");
	var pubdate_cell		= getById("record_detail_pubdate_cell");
	var publisher_cell	= getById("record_detail_publisher_cell");

	var subject_cell		= getById("record_detail_subject_cell");
	var tcn_cell			= getById("record_detail_tcn_cell");
	var resource_cell		= getById("record_detail_resource_cell");
	var pic_cell			= getById("record_detail_pic_cell");

	add_css_class(title_cell,		"detail_item_cell");
	add_css_class(author_cell,		"detail_item_cell");
	add_css_class(isbn_cell,		"detail_item_cell");
	add_css_class(edition_cell,	"detail_item_cell");
	add_css_class(pubdate_cell,	"detail_item_cell");
	add_css_class(publisher_cell, "detail_item_cell");
	add_css_class(subject_cell,	"detail_item_cell");
	add_css_class(tcn_cell,			"detail_item_cell");
	add_css_class(resource_cell,	"detail_item_cell");

	title_cell.appendChild(
		createAppTextNode(normalize(record.title())));
	author_cell.appendChild(
		createAppTextNode(normalize(record.author())));
	isbn_cell.appendChild(
		createAppTextNode(record.isbn()));

	edition_cell.appendChild(
		createAppTextNode(record.edition()));
	pubdate_cell.appendChild(
		createAppTextNode(record.pubdate()));
	publisher_cell.appendChild(
		createAppTextNode(record.publisher()));

	subject_cell.appendChild(
		createAppTextNode(record.subject()));
	tcn_cell.appendChild(
		createAppTextNode(record.tcn()));




	var resource = record.types_of_resource()[0];
	var r_pic = elem("img", 
		{ src: "/images/" + resource + ".jpg" } );
	resource_cell.appendChild(r_pic);
	resource_cell.appendChild(createAppTextNode(" "));

	resource_cell.appendChild(
		createAppTextNode(record.types_of_resource()));


	pic_cell.appendChild(this.mkImage(record));

	var orgUnit = globalSelectedLocation;
	if(!orgUnit) orgUnit = globalLocation;

	this.drawCopyTrees(orgUnit, record);
}

/* sets up the cover art image */
RecordDetailPage.prototype.mkImage = function(record) {

	var isbn = record.isbn();
	if(isbn) isbn = isbn.replace(/\s+/,"");
	else isbn = "";

	var big_pic = elem("a", {
		href : "http://images.amazon.com/images/P/" +isbn + ".01.LZZZZZZZ.jpg",
		title : "Click for larger image" } );

	var img_src = "http://images.amazon.com/images/P/" +isbn + ".01.MZZZZZZZ.jpg";
	var pic = elem ( "img", { src : img_src }, { border : "0px none" });
	big_pic.appendChild(pic);

	return big_pic;
}


/* if sync, it is a synchronous call */
RecordDetailPage.prototype.grabCopyTree = function(record, orgUnit, callback, sync) {

	var orgIds = new Array();
	if(orgUnit.constructor == Array) {
		for(var x = 0; x < orgUnit.length; x++) {
			orgIds.push(orgUnit[x].id());
		}
	} else {
		orgIds.push(orgUnit.id());
	}

	debug("Grabbing copy tree for " + orgIds);

	var req = new RemoteRequest(
		"open-ils.cat",
		"open-ils.cat.asset.copy_tree.retrieve",
		null, record.doc_id(), orgIds );	

	var obj = this;

	if(sync) { /* synchronous call */
		req.send(true);
		callback(req.getResultObject());

	} else {
		req.setCompleteCallback( 
			function(r) { callback(r.getResultObject()); });
		req.send();
	}
}


/* entry point for displaying the copy details pane */
RecordDetailPage.prototype.drawCopyTrees = function(orgUnit, record) {

	debug("Got ORG unit " + orgUnit);
	orgUnit = findOrgUnit(orgUnit);
	if(orgUnit == null) return;

	debug("OrgUnit depth is: " + findOrgType(orgUnit.ou_type()).depth());
	removeChildren(this.treeDiv);

	/* display a 'hold on' message */
	this.treeDiv.appendChild(elem("br"));
	this.treeDiv.appendChild(elem("br"));

	var depth = parseInt(findOrgType(orgUnit.ou_type()).depth());
	if(depth != 0) {
		this.treeDiv.appendChild(elem("div", null, null, "Loading copy information..."));
		if(parseInt(findOrgType(orgUnit.ou_type()).can_have_vols()))
			this.displayParentLink(orgUnit, record);
		this.displayTrees(orgUnit, record);
	}
}


/* displays a link to view info for the parent org 
	if showMe == true, we don't search for the parent, 
	but use the given orgUnit as the link point */
RecordDetailPage.prototype.displayParentLink = function(orgUnit, record, showMe) {

	var region = orgUnit;
	if(!showMe)
		region = findOrgUnit(orgUnit.parent_ou());

	var href = this.parentLink;
	removeChildren(href);

	href.appendChild(createAppTextNode(
		"View Volumes/Copies for " + region.name()));

	var obj = this;
	href.onclick = function() { 

		removeChildren(obj.treeDiv);
		obj.treeDiv.appendChild(elem("br"));
		obj.treeDiv.appendChild(elem("br"));
		obj.treeDiv.appendChild(elem("div", null, null, "Loading copy information..."));

		/* allows the above message to be displayed */
		setTimeout(function() { obj.displayTrees(region, record, true) }, 100); 

		if(showMe)
			obj.displayParentLink(orgUnit, record);
		else
			obj.displayParentLink(orgUnit, record, true);
	}

	var reg_div = createAppElement("div");
	//reg_div.appendChild(href);
	this.mainBox.insertBefore(reg_div, this.treeDiv);
}

/* displays copy info for orgUnit and all of it's children.
	if orgUnit is a region (depth == 1), then we just show
	all of our children.  if it's a branch, sub-branch, etc.
	the current branch as well as all of it's children are displayed */
RecordDetailPage.prototype.displayTrees = function(orgUnit, record, sync) {
	var obj = this;
	var orgs = orgUnit.children();
	if(!orgs) orgs = [];

	if(parseInt(findOrgType(orgUnit.ou_type()).can_have_vols()))
		orgs.unshift(orgUnit);

	this.grabCopyTree(record, orgs, 
		function(tree) {
			obj.displayCopyTree(tree, "Volumes/Copies for " + orgUnit.name() );
		}, sync );
}


/*  displays a single copy tree */
RecordDetailPage.prototype.displayCopyTree = function(tree, title) {
	
	debug("Displaying copy tree for " + title);

	if(!globalCopyStatus) grabCopyStatus(); /* just to be safe */

	var treeDiv =  this.treeDiv;
	removeChildren(treeDiv);
	add_css_class( treeDiv, "copy_tree_div" );

	var table = createAppElement("table");
	add_css_class(table, "copy_tree_table");
	var header_row = table.insertRow(table.rows.length);
	add_css_class(header_row, "top_header_row");
	var header = header_row.insertCell(header_row.cells.length);
	header.colSpan = 3;
	header.setAttribute("colspan", 3);
	var bold = createAppElement("b");
	bold.appendChild(createAppTextNode(title));
	header.appendChild(bold);

	var row2		= table.insertRow(table.rows.length);
	var cell1	= row2.insertCell(row2.cells.length);
	var cell2	= row2.insertCell(row2.cells.length);
	var cell3	= row2.insertCell(row2.cells.length);
	var cell4	= row2.insertCell(row2.cells.length);
	var cell5	= row2.insertCell(row2.cells.length);

	cell1.appendChild(createAppTextNode("Library"));
	cell2.appendChild(createAppTextNode("Callnumber"));
	cell3.appendChild(createAppTextNode("Barcode(s)"));
	cell4.appendChild(createAppTextNode("Location"));
	cell5.appendChild(createAppTextNode("Availability"));

	add_css_class(cell1, "detail_header_cell");
	add_css_class(cell2, "detail_header_cell");
	add_css_class(cell3, "detail_header_cell");
	add_css_class(cell4, "detail_header_cell");
	add_css_class(cell5, "detail_header_cell");

	if(tree.length == 0) {
		var row = table.insertRow(table.rows.length);
		row.insertCell(0).appendChild(
			createAppTextNode("No copies available for this location"));
	}

	var libsVisited = new Array();
	var x = 0;
	for( var i in tree ) {
		var row = table.insertRow(table.rows.length);
		if(x%2) add_css_class(row, "copy_tree_row_highlight");
		var volume = tree[i];

		var cell1 = row.insertCell(row.cells.length);
		add_css_class(cell1, "detail_item_cell");


		/* here we don't want to repeat the same libs name */
		if(find_list( libsVisited,
				function(name) { 

				return (name == findOrgUnit(volume.owning_lib()).name()); })) {
			cell1.appendChild(createAppTextNode(" "));

		} else {
			var name = findOrgUnit(volume.owning_lib()).name();
			cell1.appendChild(createAppTextNode(name));
			libsVisited.push(name);
		}

		var cell2 = row.insertCell(row.cells.length);
		add_css_class(cell2, "detail_item_cell");
		cell2.appendChild(createAppTextNode(volume.label()));

		var cell3 = row.insertCell(row.cells.length);
		add_css_class(cell3, "detail_item_cell");
		cell3.appendChild(createAppTextNode(" "));

		var cell4 = row.insertCell(row.cells.length);
		add_css_class(cell4, "detail_item_cell");
		cell4.appendChild(createAppTextNode(" "));

		var cell5 = row.insertCell(row.cells.length);
		add_css_class(cell4, "detail_item_cell");
		cell5.appendChild(createAppTextNode(" "));
		
		var copies = volume.copies();
		var c = 0;

		while(c < copies.length) {

			var copy = copies[c];
			var loc = findCopyLocation(copy.location()).name();

			if(c == 0) { /* put the first barcode in the same row as the callnumber */

				removeChildren(cell3);
				cell3.appendChild(createAppTextNode(copy.barcode()));

				removeChildren(cell4);
				cell4.appendChild(createAppTextNode(loc));

				removeChildren(cell5);
				var status = find_list(globalCopyStatus, 
						function(i) { return (i.id() == copy.status());} );

				var sname = "";
				if(status) sname = status.name();
				cell5.appendChild(createAppTextNode(sname));

			} else {

				var row = table.insertRow(table.rows.length);
				if(x%2) add_css_class(row, "copy_tree_row_highlight");
				row.insertCell(0).appendChild(createAppTextNode(" "));
				row.insertCell(1).appendChild(createAppTextNode(" "));

				var ce = row.insertCell(2);
				var loc_cell = row.insertCell(3);
				var status_cell = row.insertCell(4);

				add_css_class(ce, "detail_item_cell");
				add_css_class(loc_cell, "detail_item_cell");
				add_css_class(status_cell, "detail_item_cell");

				ce.appendChild(createAppTextNode(copy.barcode()));
				loc_cell.appendChild(createAppTextNode(loc));

				var status = find_list(globalCopyStatus, 
						function(i) { return (i.id() == copy.status());} );
				var sname = "";
				if(status) sname = status.name();
				status_cell.appendChild(mktext(sname))
			}

			c++;
		}
		x++;
	}

	treeDiv.appendChild(table);
}



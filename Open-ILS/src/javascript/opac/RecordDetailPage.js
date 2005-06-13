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
	this.draw();
}

RecordDetailPage.prototype.draw = function() {
	this.mainBox = getById("record_detail_main_box");
	this.fetchRecord(paramObj.__record); /* sets this.record */
	this.viewMarc = getById("record_detail_view_marc");
	

}

RecordDetailPage.prototype.setViewMarc = function(record) {
	var marcb = elem( "a", 
		{ href:"javascript:void(0)" }, {}, "View Marc" );

	debug("Setting up view marc callback with record " + record.doc_id());
	var func = buildViewMARCWindow(record);
	marcb.onclick = func;
	this.viewMarc.appendChild(marcb);
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
			obj.drawRecord(obj.record); 
			obj.setViewMarc(obj.record);
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

	add_css_class(title_cell, "detail_item_cell");
	add_css_class(author_cell, "detail_item_cell");
	add_css_class(isbn_cell, "detail_item_cell");
	add_css_class(edition_cell, "detail_item_cell");
	add_css_class(pubdate_cell, "detail_item_cell");
	add_css_class(publisher_cell, "detail_item_cell");
	add_css_class(subject_cell, "detail_item_cell");
	add_css_class(tcn_cell, "detail_item_cell");
	add_css_class(resource_cell, "detail_item_cell");

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
	resource_cell.appendChild(
		createAppTextNode(record.types_of_resource()));

	this.drawCopyTree(record);
}

RecordDetailPage.prototype.grabCopyTree = function(record, orgUnit, callback) {
	debug("Grabbing copy tree for " + orgUnit.name() );

	var req = new RemoteRequest(
		"open-ils.cat",
		"open-ils.cat.asset.copy_tree.retrieve",
		null, record.doc_id(), orgUnit.id() );	

		var obj = this;
		req.setCompleteCallback( 
			function(r) { callback(r.getResultObject()); });

		req.send();
}


RecordDetailPage.prototype.drawCopyTree = function(record) {

	var user = UserSession.instance();

	/*
	if(user && user.connected) 
		orgUnit = findOrgUnit(user.userObject.home_ou());
	else {
	*/
	var orgUnit = globalSelectedLocation;
	if(!orgUnit)
		orgUnit = globalLoction;
	
	var obj = this;
	debug("We're connected, collecting local copies");
	this.grabCopyTree(record, orgUnit, 
		function(tree) {
			obj.displayCopyTree(tree, "Local Volumes/Copies for " 
				+ orgUnit.name(), "local_copy_tree" );
			obj.addExtraLinks(record);
		}
	);	
}


RecordDetailPage.prototype.addExtraLinks = function(record) {

	var user = UserSession.instance();

	var href = createAppElement("a");
	href.setAttribute("href", "javascript:void(0)");
	var trail = orgNodeTrail(findOrgUnit(user.userObject.home_ou()));
	var region = trail[1]; /* org trail starts at top, region is second */	
	href.appendChild(createAppTextNode("-> See Volumes/Copies for " + region.name()));

	var obj = this;
	href.onclick = function() {
		var thingy = getById("system_copy_tree");
		if(thingy) {
			obj.mainBox.removeChild(thingy);
		} else {
			obj.grabCopyTree(record, region, 
				function(tree) {
					if(tree) debug("In grabb copy callback for system with tree");
					obj.displayCopyTree(tree, 
						"Volumes/Copies for " + region.name(), "system_copy_tree");
				}
			);
		}
	}

	var reg_div = createAppElement("div");
	reg_div.appendChild(href);
	this.mainBox.appendChild(createAppElement("br"));
	this.mainBox.appendChild(createAppElement("br"));
	this.mainBox.appendChild(reg_div);

}

/* id is the id of the chunk we're adding to the page, prevents duplicates */
RecordDetailPage.prototype.displayCopyTree = function(tree, title, id) {
	
	var treeDiv = createAppElement("div");
	treeDiv.appendChild(createAppElement("br"));
	treeDiv.appendChild(createAppElement("br"));

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

	cell1.appendChild(createAppTextNode("Callnumber"));
	cell2.appendChild(createAppTextNode("Volume Owned By"));
	cell3.appendChild(createAppTextNode("Barcode"));

	add_css_class(cell1, "detail_header_cell");
	add_css_class(cell2, "detail_header_cell");
	add_css_class(cell3, "detail_header_cell");

	for( var i in tree ) {
		var row = table.insertRow(table.rows.length);
		var volume = tree[i];

		var cell1 = row.insertCell(row.cells.length);
		add_css_class(cell1, "detail_item_cell");
		cell1.appendChild(createAppTextNode(volume.label()));
		var cell2 = row.insertCell(row.cells.length);
		add_css_class(cell2, "detail_item_cell");
		cell2.appendChild(createAppTextNode(
			findOrgUnit(volume.owning_lib()).name()));
		
		var copies = volume.copies();
		var c = 0;
		while(c < copies.length) {
			var copy = copies[c];

			var row = table.insertRow(table.rows.length);
			row.insertCell(0);
			row.insertCell(1);
			var ce = row.insertCell(2);
			add_css_class(ce, "detail_item_cell");
			ce.appendChild(createAppTextNode(copy.barcode()));
			c++;
		}
	}

	treeDiv.appendChild(table);
	treeDiv.id = id;
	this.mainBox.appendChild(treeDiv);
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





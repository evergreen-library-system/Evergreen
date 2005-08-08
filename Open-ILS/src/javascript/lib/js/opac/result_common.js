

/* set the search result info, number of hits, which results we're 
	displaying, links to the next/prev pages, etc. */
function resultSetInfo() { 
	var c;  
	if( getDisplayCount() > (getHitCount() - getOffset()))  c = getHitCount();
	else c = getDisplayCount() + getOffset();

	var pages = parseInt(getHitCount() / getDisplayCount()) + 1;
	G.ui.result.current_page.appendChild(text( (getOffset()/getDisplayCount()) + 1));
	G.ui.result.num_pages.appendChild(text(pages + ")"));

	var o = getOffset();

	if( !((o + getDisplayCount()) >= getHitCount()) ) {

		var args = {};
		args[PARAM_OFFSET] = o + getDisplayCount();
		G.ui.result.next_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.next_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = getHitCount() - (getHitCount() % getDisplayCount());
		G.ui.result.end_link.setAttribute("href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.end_link, config.css.result.nav_active);
	}

	if( o > 0 ) {

		var args = {};
		args[PARAM_OFFSET] = o - getDisplayCount();
		G.ui.result.prev_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.prev_link, config.css.result.nav_active);

		args[PARAM_OFFSET] = 0;
		G.ui.result.home_link.setAttribute( "href", buildOPACLink(args)); 
		addCSSClass(G.ui.result.home_link, config.css.result.nav_active);
	}

	G.ui.result.offset_start.appendChild(text(o + 1));
	G.ui.result.offset_end.appendChild(text(c));
	G.ui.result.result_count.appendChild(text(getHitCount()));
	unHideMe(G.ui.result.info);

}


/* display the record info in the record display table */
function resultDisplayRecord(rec, rowtemplate, is_mr) {

	if(rec == null) rec = new mvr(); /* if we return we won't build some important UI components */

	//alert("building record " + rec.title());

	/* hide the 'now loading...' message */
	hideMe(G.ui.common.loading);

	var r = rowtemplate.cloneNode(true);

	var pic = findNodeByName(r, config.names.result.item_jacket);
	pic.setAttribute("src", buildISBNSrc(cleanISBN(rec.isbn())));


	var title_link = findNodeByName(r, config.names.result.item_title);
	var author_link = findNodeByName(r, config.names.result.item_author);

	if( is_mr )  buildTitleLink(rec, title_link); 
	else  buildTitleDetailLink(rec, title_link); 
	buildAuthorLink(rec, author_link); 

	var countsrow = findNodeByName(r, config.names.result.counts_row);

	/* adjust the width according to how many org counts are added */
	findNodeByName(r, "result_table_title_cell").width = 
		resultAddCopyCounts(countsrow, rec) + "%";

	table.appendChild(r);

}


/* -------------------------------------------------------------------- */
/* dynamically add the copy count rows based on the org type 
	'countsrow' is the row into which we will add TD's to hold
	the copy counts 
	This code generates copy count cells with an id of

	'copy_count_cell_<depth>_<record_id>' for later insertion
	of copy counts

	return the percent width left over after the each count is added. 
	if 3 counts are added, returns 100 - (cell.width * 3)
 */

function resultAddCopyCounts(countsrow, rec) {

	var ccell = findNodeByName(countsrow, config.names.result.count_cell);


	var nodes = orgNodeTrail(findOrgUnit(getLocation()));
	var node = nodes[0];
	var type = findOrgType(node.ou_type());
	ccell.id = "copy_count_cell_" + type.depth() + "_" + rec.doc_id();
	ccell.title = type.opac_label();
	addCSSClass(ccell, "copy_count_cell_even");


	var lastcell = ccell;

	if(nodes[1]) {

		var x = 1;
		var d = findOrgDepth(nodes[1]);
		var d2 = findOrgDepth(nodes[nodes.length -1]);

		for( var i = d; i <= d2 ; i++ ) {
	
			ccell = ccell.cloneNode(true);

			if((i % 2))
				removeCSSClass(ccell, "copy_count_cell_even");
			else
				addCSSClass(ccell, "copy_count_cell_even");

			var node = nodes[x++];
			var type = findOrgType(node.ou_type());
	
			ccell.id = "copy_count_cell_" + type.depth() + "_" + rec.doc_id();
			ccell.title = type.opac_label();
			countsrow.insertBefore(ccell, lastcell);
			lastcell = ccell;

		}
	}

	return 100 - (nodes.length * 8);

}


/* collect copy counts for a record using method 'methodName' */
function resultCollectCopyCounts(rec, methodName) {
	if(rec == null || rec.doc_id() == null) return;
	var req = new Request(methodName, getLocation(), rec.doc_id() );
	req.callback(function(r){ resultDisplayCopyCounts(rec, r.getResultObject()); });
	req.send();
}


/* display the collected copy counts */
function resultDisplayCopyCounts(rec, copy_counts) {
	if(copy_counts == null || rec == null) return;
	var i = 0;
	while(copy_counts[i] != null) {
		var cell = getId("copy_count_cell_" + i +"_" + rec.doc_id());
		cell.appendChild(text(copy_counts[i].available + " / " + copy_counts[i].count));
		i++;
	}
}






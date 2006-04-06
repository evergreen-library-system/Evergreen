var cpdTemplate;
var cpdCounter = 0;
var cpdNodes = {};

function cpdBuild( contextTbody, contextRow, record, callnumber, orgid, depth ) {

	var i = cpdCheckExisting(contextRow);
	if(i) return i;

	if(!cpdTemplate) cpdTemplate = $('rdetail_volume_details_row');
	var templateRow = cpdTemplate.cloneNode(true);
	templateRow.id = 'cpd_row_' + (cpdCounter++);

	/* shove a dummy a tag in before the context previous sibling */
	contextTbody.insertBefore( elem('a',{name:'slot_'+templateRow.id}), contextRow.previousSibling);
	goTo('#slot_'+templateRow.id);

	unHideMe(templateRow);

	var req = new Request(FETCH_VOLUME_BY_INFO, callnumber, record.doc_id(), orgid);
	req.callback(cpdFetchCopies);

	req.request.args = { 
		contextTbody	: contextTbody,
		contextRow		: contextRow,
		record			: record,
		callnumber		: callnumber, 
		orgid				: orgid,
		depth				: depth,
		templateRow		: templateRow,
	};

	if( contextRow.nextSibling ) 
		contextTbody.insertBefore( templateRow, contextRow.nextSibling );
	else
		contextTbody.appendChild( templateRow );

	req.send();
	cpdNodes[templateRow.id] = { visible : true, templateRow : templateRow };
	return templateRow.id;
}


/* hide any open tables and if we've already 
	fleshed this cn, just unhide it */
function cpdCheckExisting( contextRow ) {

	var existingid;
	var next = contextRow.nextSibling;

	if( next && next.getAttribute('templateRow') ) {
		var obj = cpdNodes[next.id];
		if(obj.visible) hideMe(obj.templateRow);
		else unHideMe(obj.templateRow);
		obj.visible = !obj.visible;
		existingid = next.id;
	}

	for( var o in cpdNodes ) {
		var node = cpdNodes[o];
		if( existingid && o == existingid ) continue;
		node.visible = false;
		hideMe(node.templateRow);
		removeCSSClass(node.templateRow.previousSibling, 'rdetail_context_row');
	}

	addCSSClass(contextRow, 'rdetail_context_row');
	if(existingid) return existingid;
	return null;
}

function cpdFetchCopies(r) {
	var args = r.args;
	args.cn	= r.getResultObject();

	/* set up the cn browser launch point */
	/*
	var href = 'javascript:rdetailShowCNBrowse("' + 
			args.callnumber + '", "'+args.depth+'");';
	$n(args.templateRow, 'launch_shelf_browser').setAttribute('href', href);
	*/


	var req = new Request(FETCH_COPIES_FROM_VOLUME, args.cn.id());
	req.request.args = args;
	req.callback(cpdDrawCopies);
	req.send();
}

function cpdDrawCopies(r) {

	var copies		= r.getResultObject();
	var args			= r.args;
	var copytbody	= $n(args.templateRow, 'copies_tbody');
	var copyrow		= copytbody.removeChild($n(copytbody, 'copies_row'));

	for( var i = 0; i < copies.length; i++ ) {
		var row = copyrow.cloneNode(true);
		var copyid = copies[i];
		var req = new Request(FETCH_COPY, copies[i]);
		req.callback(cpdDrawCopy);
		req.request.args = r.args;
		req.request.row = row;
		req.send();
		copytbody.appendChild(row);
	}
}

function cpdDrawCopy(r) {
	var copy = r.getResultObject();
	var row  = r.row;

	$n(row, 'barcode').appendChild(text(copy.barcode()));
	$n(row, 'location').appendChild(text(cpdGetLocation(copy).name()));

	for( i = 0; i < cp_statuses.length; i++ ) {
		var c = cp_statuses[i];
		if( c.id() == copy.status() )
		$n(row, 'status').appendChild(text(c.name()));
	}

}


var copyLocations;
function cpdGetLocation(copy) {

	if(!copyLocations) {
		var req = new Request(FETCH_COPY_LOCATIONS);	
		req.send(true);
		copyLocations = req.result();
	}

	return grep(copyLocations, 
		function(l) { return l.id() == copy.location() } )[0];
}


/*

var rdetailCNDetailsRow;
var rdetailCNDetailContainerRow;
function rdetailShowCNDetails3(r) {

	var copies = r.getResultObject();
	var cn = r._cn;
	var wrapperrow = r._row;

	var parent = $('rdetail_copy_info_tbody');
	var tbody = $('rdetail_cn_copies_tbody');

	if(!rdetailCNDetailsRow) {
		rdetailCNDetailsRow = tbody.removeChild($('rdetail_cn_copies_row'));
		rdetailCNDetailContainerRow = $('rdetail_volume_details_row');
	}
	
	removeChildren(tbody);

	for( var i = 0; i != copies.length; i++ ) {
		var row = rdetailCNDetailsRow.cloneNode(true);
		var copyid = copies[i];
		var req = new Request(FETCH_COPY, copyid);
		req.callback(rdetailShowCNCopy);
		req.request._cn = cn;
		req.request._tbody = tbody;
		req.request._row = row;
		req.send();
		tbody.appendChild(row);
	}

	var oldrow = $('rdetail_cn_details_div').parentNode.parentNode;

	unHideMe($('rdetail_cn_details_div'));
	newrow = rdetailCNDetailContainerRow;

	removeCSSClass(newrow.previousSibling, 'rdetail_context_row');

	var td = newrow.getElementsByTagName('td')[0];
	td.appendChild($('rdetail_cn_details_div'));

	addCSSClass(wrapperrow, 'rdetail_context_row');
	if( wrapperrow.nextSibling ) 
		parent.insertBefore( newrow, wrapperrow.nextSibling );
	else
		parent.appendChild( newrow );
}

function rdetailShowCNCopy(r) {
	var copy = r.getResultObject();
	var row = r._row;
	$n(row, 'barcode').appendChild(text(copy.barcode()));

	for( i = 0; i < cp_statuses.length; i++ ) {
		var c = cp_statuses[i];
		if( c.id() == copy.status() )
			$n(row, 'status').appendChild(text(c.name()));
	}

	rdetailSetCopyLocation( row, copy );
}

var copyLocations;
function rdetailSetCopyLocation( row, copy ) {

	if(!copyLocations) {
		var req = new Request(FETCH_COPY_LOCATIONS);	
		req.send(true);
		copyLocations = req.result();
	}

	var location = grep(copyLocations, 
		function(l) { return l.id() == copy.location() } )[0];

	$n(row, 'location').appendChild(text(location.name()));
}


*/


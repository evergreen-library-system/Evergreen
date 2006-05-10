var cpdTemplate;
var cpdCounter = 0;
var cpdNodes = {};

function cpdBuild( contextTbody, contextRow, record, callnumber, orgid, depth ) {
var i = cpdCheckExisting(contextRow);
	if(i) return i;

	var counter = cpdCounter++;

	/* yank out all of the template rows */
	if(!cpdTemplate) cpdTemplate = $('rdetail_volume_details_row');
	var templateRow = cpdTemplate.cloneNode(true);
	templateRow.id = 'cpd_row_' + counter;

	/* shove a dummy a tag in before the context previous sibling */
	/*
	contextTbody.insertBefore( 
		elem('a',{name:'slot_'+templateRow.id}), contextRow.previousSibling);
	goTo('#slot_'+templateRow.id);
	*/

	unHideMe(templateRow);

	var print = $n(templateRow,'print');
	print.onclick = function() { cpdBuildPrintPane(
		contextRow, record, callnumber, orgid, depth) };

	var mainTbody = $n(templateRow, 'copies_tbody');
	var extrasRow = mainTbody.removeChild($n(mainTbody, 'copy_extras_row'));

	var req = new Request(FETCH_VOLUME_BY_INFO, callnumber, record.doc_id(), orgid);
	req.callback(cpdFetchCopies);

	req.request.args = { 
		contextTbody	: contextTbody, /* tbody that holds the contextrow */
		contextRow		: contextRow, /* the row our new row will be inserted after */
		record			: record,
		callnumber		: callnumber, 
		orgid				: orgid,
		depth				: depth,
		templateRow		: templateRow, /* contains everything */
		mainTbody		: mainTbody, /* holds the copy rows */
		extrasRow		: extrasRow, /* wrapper row for all extras */
		counter			: counter
	};

	if( contextRow.nextSibling ) 
		contextTbody.insertBefore( templateRow, contextRow.nextSibling );
	else
		contextTbody.appendChild( templateRow );

	req.send();
	_debug('creating new details row with id ' + templateRow.id);
	cpdNodes[templateRow.id] = { templateRow : templateRow };
	return templateRow.id;
}


function cpdBuildPrintWindow(record, orgid) {
	/*
	var win;

	if( isXUL() ) {

		win = xulG.window_open(
			'data:text/html,' +
			window.escape('<html><head><title></title></head><body>AAHHH</body></html>'),
			'', 
			'chrome,resizable,width=700,height=500'); 
		alert(win.document.getElementsByTagName('body'));
		alert('obj: ' + win.document.getElementsByTagName('body')[0]);
		alert(win.document.getElementsByTagName('body')[0].textContent);
		win.document.getElementsByTagName('body')[0].appendChild(text('TESTING TESTING'));

	} else {
		win = window.open('','', 'resizable,width=700,height=500'); 
	}
	*/

	var div = $('rdetail_print_details').cloneNode(true);
	div.id = "";

	$n(div, 'lib').appendChild(text(findOrgUnit(orgid).name()));
	$n(div, 'title').appendChild(text(record.title()));
	$n(div, 'author').appendChild(text(record.author()));
	$n(div, 'edition').appendChild(text(record.edition()));
	$n(div, 'pubdate').appendChild(text(record.pubdate()));
	$n(div, 'publisher').appendChild(text(record.publisher()));
	$n(div, 'phys').appendChild(text(record.physical_description()));


	return div;
}

function cpdStylePopupWindow(div) {
	var tds = div.getElementsByTagName('td');
	for( var i = 0; i < tds.length ; i++ ) {
		var sty = tds[i].getAttribute('style');
		if(!sty) sty = "";
		tds[i].setAttribute('style', sty + 'padding: 2px; border: 1px solid #F0F0E0;');
	}
}


/* builds a friendly print window for this CNs data */
function cpdBuildPrintPane(contextRow, record, callnumber, orgid, depth) {

	/*
	var arr = cpdBuildPrintWindow( record, orgid);
	var win = arr[0];
	var div = arr[1];
	*/

	var div = cpdBuildPrintWindow( record, orgid);

	$n(div, 'cn').appendChild(text(callnumber));

	unHideMe($n(div, 'copy_header'));

	var subtbody = $n(contextRow.nextSibling, 'copies_tbody');
	var rows = subtbody.getElementsByTagName('tr');

	for( var r = 0; r < rows.length; r++ ) {
		var row = rows[r];
		if(!row) continue;
		var clone = row.cloneNode(true);
		var links = clone.getElementsByTagName('a');
		for( var i = 0; i < links.length; i++ ) 
			links[i].style.display = 'none';

		$n(div, 'tbody').appendChild(clone);
	}

	cpdStylePopupWindow(div);
	/*
	win.document.body.innerHTML = div.innerHTML;
	*/
	openWindow( div.innerHTML);
}



/* hide any open tables and if we've already 
	fleshed this cn, just unhide it */
function cpdCheckExisting( contextRow ) {

	var existingid;
	var next = contextRow.nextSibling;

	if( next && next.getAttribute('templateRow') ) {
		var obj = cpdNodes[next.id];
		if(obj.templateRow.className.match(/hide_me/)) 
			unHideMe(obj.templateRow);
		else hideMe(obj.templateRow);
		existingid = next.id;
	}

	if(existingid) _debug('row exists with id ' + existingid);

	for( var o in cpdNodes ) {
		var node = cpdNodes[o];
		if( existingid && o == existingid ) continue;
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

	r.args.copy = copy;

	$n(row, 'barcode').appendChild(text(copy.barcode()));
	$n(row, 'location').appendChild(text(cpdGetLocation(copy).name()));

	for( i = 0; i < cp_statuses.length; i++ ) {
		var c = cp_statuses[i];
		if( c.id() == copy.status() ) {
			$n(row, 'status').appendChild(text(c.name()));
			break;
		}
	}

	var req = new Request(FETCH_COPY_NOTES, { pub : 1, itemid : copy.id() } );
	req.request.args = r.args;
	req.request.args.copyrow = row;
	req.callback(cpdShowNotes);
	req.send();

	req = new Request(FETCH_COPY_STAT_CATS, { copyid : copy.id(), "public" : 1 });
	req.request.args = r.args;
	req.request.args.copyrow = row;
	req.callback(cpdShowStats);
	req.send();
}

function _cpdExtrasInit(args) {

	var newrid	= 'extras_row_' + args.copy.barcode();
	var newrow	= $(newrid);
	if(!newrow) newrow = args.extrasRow.cloneNode(true);
	var tbody	= $n(newrow, 'extras_tbody');
	var rowt		= $n(tbody, 'extras_row');
	newrow.id	= newrid;

	var cr = args.copyrow;
	var nr = cr.nextSibling;
	var np = args.mainTbody;

	/* insert the extras row into the main table */
	if(nr) np.insertBefore( newrow, nr );
	else np.appendChild(newrow);

	var link = $n(args.copyrow, 'details_link');
	var link2 = $n(args.copyrow, 'less_details_link');
	var id = newrow.id;
	link.id = id + '_morelink';
	link2.id = id + '_lesslink';
	unHideMe(link);
	hideMe(link2);

	link.setAttribute('href', 
			'javascript:unHideMe($("'+link2.id+'")); hideMe($("'+link.id+'"));unHideMe($("'+newrow.id+'"));');

	link2.setAttribute('href', 
			'javascript:unHideMe($("'+link.id+'")); hideMe($("'+link2.id+'"));hideMe($("'+newrow.id+'"));');

	return [ tbody, rowt ];
}

function cpdShowNotes(r) {
	var notes = r.getResultObject();

	if(notes.length > 0) {

		var a = _cpdExtrasInit(r.args);
		var tbody = a[0];
		var rowt = a[1];

		for( var n in notes ) {
			var note = notes[n];
			var row = rowt.cloneNode(true);
			$n(row, 'key').appendChild(text(note.title()));
			$n(row, 'value').appendChild(text(note.value()));
			unHideMe($n(row, 'note'));
			unHideMe(row);
			tbody.appendChild(row);
		}
	}
}


function cpdShowStats(r) {
	var entries = r.getResultObject();

	if(entries.length > 0) {
		
		var a = _cpdExtrasInit(r.args);
		var tbody = a[0];
		var rowt = a[1];

		for( var n in entries ) {
			var entry = entries[n];
			var row = rowt.cloneNode(true);
			$n(row, 'key').appendChild(text(entry.stat_cat().name()));
			$n(row, 'value').appendChild(text(entry.value()));
			unHideMe($n(row, 'cat'));
			unHideMe(row);
			tbody.appendChild(row);
		}
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






/* XXX allow to pass in a 'local' var so the links back into the opac can be localized */
/* maybe also a 'skin' var */

function bbInit() {
	var cgi	= new CGI();
	var bb	= cgi.param('bb');
	if(!bb) { unHideMe($('not_found')); return; }
	var req = new Request(FLESH_PUBLIC_CONTAINER, 'biblio', bb);
	req.callback( bbShow );
	req.send();
}


var template;
function bbShow(r) {

	var bb = r.getResultObject();
	if(!bb || !bb.pub()) { unHideMe($('not_found')); return; }
	$('bb_name').appendChild(text(bb.name()));

	var tbody = $('tbody');
	if(!template) template = tbody.removeChild($('row_template'));

	for( var i in bb.items() ) 
		tbody.appendChild(bbShowItem( template, bb.items()[i] ));
}

function bbShowItem( template, item ) {
	var row = template.cloneNode(true);

	var req = new Request( FETCH_RMODS, item.target_biblio_record_entry() );
	req.request.tlink = $n(row, 'title');
	req.request.alink = $n(row, 'author');
	req.request.blink = $n(row, 'by');

	req.callback( function(r) { 
		var rec = r.getResultObject();
		buildTitleDetailLink(rec, r.tlink); 
		r.tlink.setAttribute('href', '/opac/en-US/skin/default/xml/rdetail.xml?r='+rec.doc_id());
		r.alink.appendChild(text(rec.author()));
		unHideMe(r.blink);
	});

	req.send();
	return row;
}

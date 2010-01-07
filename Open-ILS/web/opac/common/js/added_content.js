/**
* This function should return a URL which points to the book cover image based on ISBN.
*/


function buildISBNSrc(isbn, size) {
	size = (size) ? size : 'small';
	var protocol = (OILS_OPAC_STATIC_PROTOCOL) ? OILS_OPAC_STATIC_PROTOCOL + ':' : location.protocol;
    if(OILS_OPAC_IMAGES_HOST)
        return protocol + '//' + OILS_OPAC_IMAGES_HOST + size + '/' + isbn;
	return '../../../../extras/ac/jacket/'+size+'/'+isbn;
}      


function acMakeURL(type, key) {
	return '../../../../extras/ac/' + type + '/html/' + key;
}


function acCollectData( key, callback ) {
	var context = { key : key, callback: callback, data : {} };
	acCollectItem(context, 'reviews');
	acCollectItem(context, 'toc');
	acCollectItem(context, 'excerpt');
	acCollectItem(context, 'anotes');
}

function acCheckDone(context) {
	if(	context.data.reviews && context.data.reviews.done &&
			context.data.toc		&& context.data.toc.done &&
			context.data.excerpt && context.data.excerpt.done &&
			context.data.anotes	&& context.data.anotes.done ) {

		if(context.callback) context.callback(context.data);
	}
}

function acCollectItem(context, type) {
	var req = buildXMLRequest();
	req.open('GET', acMakeURL(type, context.key), true);
	req.onreadystatechange = function() {
		if( req.readyState == 4 ) {
			context.data[type] = { done : true }

			if(IE) {

				/* Someone please explain why IE treats status 404 as status 200?? 
					On second thought, don't bother.
				*/
				if( ! req.responseText.match(
					/The requested URL.*was not found on this server/) )
					context.data[type].html = req.responseText;

			} else {
				if( req.status != 404 ) 
					context.data[type].html = req.responseText;
			}
			acCheckDone(context);
		}
	}
	req.send(null);
}



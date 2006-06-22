/**
* This function should return a URL which points to the book cover image based on ISBN.
* Ideally, this should point to some type of added content service.
* The example below uses Amazon... *use at own risk*
*/

function buildISBNSrc(isbn) {
	//return "http://images.amazon.com/images/P/" + isbn + ".01._SCMZZZZZZZ_.jpg";
	//return '../../../../jackets/'+isbn;
	return '../../../../extras/jacket/'+isbn;
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
			if( req.status != 404 ) 
				context.data[type].html = req.responseText;
			acCheckDone(context);
		}
	}
	req.send(null);
}



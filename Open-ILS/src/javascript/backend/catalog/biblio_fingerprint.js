//var marcdoc = new XML(environment.marc);
//var marc_ns = new Namespace('http://www.loc.gov/MARC21/slim');

var modsdoc = new XML(environment.mods);
var mods_ns = new Namespace('http://www.loc.gov/mods/');

//var mods3_ns = new Namespace('http://www.loc.gov/mods/v3');

default xml namespace = mods_ns;

var t = null;
var a = null;

function extract_typed_title( ti ) {

	try {
		var types = ['uniform','translated','alternative'];
		for ( var j in types ) {
			for ( var i in ti ) {
				if (ti[i].attribute("type") == types[j])
					return  ti[i];
			}
		}

	} catch (e) {
		log_debug(e);
		return ti[0];
	}
}

function extract_author( au ) {
	log_debug(au.toString());

	if ( au..role.length() > 0 ) au = au.(role.text == 'creator' || role.text == 'author');
	
	if ( au.(hasOwnProperty("@type")) ) {
		au = au.(@type == 'personal')[0] ||
			au.(@type == 'corporate')[0] ||
			au.(@type == 'conference')[0];
	}

	return au ? au.namePart[0] : '';
}

log_debug("typeOfResource is " + modsdoc.typeOfResource);

var quality = 0;

// Treat non-text differently
if (modsdoc.typeOfResource != 'text') {
	quality = 10;

	// Look in related items for a good title
	for ( var index in modsdoc.relatedItem.( hasOwnProperty('@type') && @type != 'series' && @type != 'host' ) ) {
		var ri = modsdoc.relatedItem[index];
		if ( ri.(!hasOwnProperty("@type") )) {
			t = extract_typed_title( ri.titleInfo.(hasOwnProperty('@type')) );
			if (!t) {
				t = ri.titleInfo[0];
				quality += 10;
			} else {
				quality += 15;
			}
		}

		if (t != null) {
			log_debug('Found ['+modsdoc.typeOfResource+'] related titleInfo node: ' + t.toXMLString());
			break;
		}
	}

	// Couldn't find a usable title in a related item
	if (t == null) {
		t = extract_typed_title( modsdoc.titleInfo );
		if (!t) {
			t = modsdoc.titleInfo[0];
			quality += 5;
		} else {
			quality += 10;
		}
	}

	log_debug('Found ['+modsdoc.typeOfResource+'] main titleInfo node: ' + t.toXMLString());

} else {
	quality = 20;

	t = extract_typed_title( modsdoc.titleInfo );

	if (t == null) {
		t = modsdoc.titleInfo[0];
		quality += 15;
	} else {
		quality += 10;
	}

	log_debug('Found ['+modsdoc.typeOfResource+'] main titleInfo node: ' + t.toXMLString());
}

var title = t.title
	.toLowerCase()
	.replace(/\[.+?\]/,'')
	.replace(/\bthe\b|\ban?d?\b|\W+/g,'');


var author = (
	( modsdoc.typeOfResource != 'text' ?
		extract_author(modsdoc.relatedItem.name) :
		extract_author(modsdoc.name) ) ||
	''
).toLowerCase().replace(/^\s*(\w+).*?$/,"$1");

result.fingerprint = title + author;
result.quality = '' + quality;


var marcdoc = new XML(environment.marc);
var marc_ns = new Namespace('http://www.loc.gov/MARC21/slim');

var modsdoc = new XML(environment.mods);
var mods_ns = new Namespace('http://www.loc.gov/mods/');

//var mods3_ns = new Namespace('http://www.loc.gov/mods/v3');

default xml namespace = mods_ns;

var t = null;
var a = null;

function extract_typed_title( ti ) {

	try {
		var types = ['uniform','translated'];
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

	try {
		if ( au..role.length() > 0 ) au = au.(role.text == 'creator' || role.text == 'author');
	
		if ( au.(hasOwnProperty("@type")) ) {
			au = au.(@type == 'personal')[0] ||
				au.(@type == 'corporate')[0] ||
				au.(@type == 'conference')[0];
		}
	} catch (e) {
		log_debug(e);
	}

	return au ? au.namePart[0] : '';
}

log_debug("typeOfResource is " + modsdoc.typeOfResource);

var quality = 0;

// Treat non-text differently
if (modsdoc.typeOfResource != 'text') {
	quality += marcdoc.datafield.length() / 2;

	// Look in related items for a good title
	for ( var index in modsdoc.relatedItem ) {
		log_debug('Looking at related items ['+modsdoc.relatedItem[index].toXMLString()+']');

		if ( modsdoc.relatedItem[index].hasOwnProperty('@type') ) {
			if ( modsdoc.relatedItem[index].@type != 'series' && modsdoc.relatedItem[index].@type != 'host' ) {
				t = extract_typed_title( modsdoc.relatedItem[index].titleInfo.(hasOwnProperty('@type')) );
				if (!t) {
					t = modsdoc.relatedItem[index].titleInfo[0];
					quality += 10;
				} else {
					quality += 15;
				}

				a = extract_author(modsdoc.relatedItem[index].name)

				if (t != null) {
					log_debug('Found ['+modsdoc.typeOfResource+'] related titleInfo node: ' + t.toXMLString());
					break;
				}
			}
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
		log_debug('Found ['+modsdoc.typeOfResource+'] main titleInfo node: ' + t.toXMLString());
	}


} else {
	quality = 20;
	quality += marcdoc.datafield.length();

	t = extract_typed_title( modsdoc.titleInfo );

	if (t == null) {
		t = modsdoc.titleInfo[0];
		quality += 15;
	} else {
		quality += 20;
	}

	log_debug('Found ['+modsdoc.typeOfResource+'] main titleInfo node: ' + t.toXMLString());
}

var title = t.title
	.toLowerCase()
	.replace(/\[.+?\]/,'')
	.replace(/\bthe\b|\ban?d?\b|\W+/g,'');


log_debug('Related item authors: [' + modsdoc.relatedItem.(hasOwnProperty('@type') && @type != 'series' && @type != 'host').name.toXMLString() + ']');
log_debug('Main authors: [' + modsdoc.name.toXMLString() + ']');

var author = a;
if (!author) {
	author = extract_author(modsdoc.name) || '';
}

author = author.toLowerCase().replace(/^\s*(\w+).*?$/,"$1");

result.fingerprint = title + author;

// now we deal with marc stuff...
default xml namespace = marc_ns;

if (marcdoc.datafield.(@tag == '040').subfield.(@code == 'a').toString().match(/DLC/)) {
	quality += 5;
	log_debug( 'got DLC bump' );
}

if (marcdoc.datafield.(@tag == '039').subfield.(@code == 'b').toString().match(/oclc/i)) {
	quality += 10;
	log_debug( 'got OCLC source bump' );
	
} else if (marcdoc.datafield.(@tag == '039').subfield.(@code == 'b').toString().match(/isxn/i)) {
	quality += 5;
	log_debug( 'got ISxN source bump' );
	
} else if (marcdoc.datafield.(@tag == '039').subfield.(@code == 'b').toString().match(/local/i)) {
	quality += 1;
	log_debug( 'got Local source bump' );
}

// XXX this has to be a string ... for now. JS::SM limitation
result.quality = '' + quality;


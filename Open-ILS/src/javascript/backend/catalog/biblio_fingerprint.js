// so we can tell if it's a book or other type
load_lib('record_type.js');

var marcdoc = new XML(environment.marc);
var marc_ns = new Namespace('http://www.loc.gov/MARC21/slim');

var modsdoc = new XML(environment.mods);
var mods_ns = new Namespace('http://www.loc.gov/mods/');
default xml namespace = marc_ns;

//var mods3_ns = new Namespace('http://www.loc.gov/mods/v3');


var rtype = recordType(marcdoc); // BKS, SER, VIS, MIX, MAP, SCO, REC, COM

var quality = 0;
var t = '';
var a = '';

try {
	// first, related items entries (700t)
	var t = marcdoc.datafield.( @tag == '700' ).subfield.( @code == 't');
	if (!t.length()) throw "No title in related item added entry (700)";
	
	a = t.parent().subfield.( @code == 'a' );

	quality += 10;

	log_debug("title: " + t);
	log_debug("author: " + a);
} catch(e) {
	log_debug(e);
	log_debug("Looking in main entries");

	var _t = '';
	try {
		try { 
			try { // uniform title
				_t = marcdoc.datafield.( @tag == '240' ).subfield.( @code == 'a' );
				if (!_t.length()) throw "No title in 240";
			} catch(e) { // translation of title
				log_debug(e);
				_t = marcdoc.datafield.( @tag == '242' ).subfield.( @code == 'a' );
				if (!_t.length()) throw "No title in 242";
			}
		} catch(e) { // alternate title (not as note) 
			log_debug(e);
			_t = marcdoc.datafield.( @tag == '246' && !(@ind1.match(/0|1/)) ).subfield.( @code == 'a' );
			if (!_t.length()) throw "No title in 246";
		}

		t = _t[0];
		log_debug("Title: " + t);
		quality += 25;

	} catch(e) {
		log_debug(e);
		log_debug("Using title proper (245a)");
		t = marcdoc.datafield.( @tag == '245' ).subfield.( @code == 'a' );
		t = t[0];
		quality += 10;
	}

	try {
		var _a = marcdoc.datafield.( @tag == '100' || @tag == '110' || @tag == '111').subfield.( @code == 'a' );
		if (!_a.length()) throw "No author in 100, 110, 111";
		
		a = _a[0];
		log_debug("Author: " + a);

	} catch(e) {
		log_debug(e);
		log_debug("Trying to find a publisher (260b)");
		a = marcdoc.datafield.( @tag == '260' ).subfield.( @code == 'b' );
		a = a[0];
	}
}

if (rtype != 'BKS') {
	quality += marcdoc.datafield.length() / 2;
} else {
	quality += 20 + marcdoc.datafield.length();
}

var title = t;
if (!title) {
	log_debug("no title found");
	title = '';
} else {
	title = title.toString();
}

title = title
	.toLowerCase()
	.replace(/\[.+?\]/,'')
	.replace(/\bthe\b|\ban?d?\b|\W+/g,'');


var author = a;
if (!author) {
	author = '';
} else {
	author = author.toString();
}

author = author.toLowerCase().replace(/^\s*(\w+).*?$/,"$1");

result.fingerprint = title + author;

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

if (extractFixedField(marcdoc, 'Lang') == 'eng') {
	quality *= 2;
	log_debug( 'got language bump for ' + extractFixedField(marcdoc, 'Lang') );
}


// XXX this has to be a string ... for now. JS::SM limitation
result.quality = '' + parseInt( '' + quality );


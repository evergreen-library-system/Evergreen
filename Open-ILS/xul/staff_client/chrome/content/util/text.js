dump('entering util/text.js\n');

if (typeof util == 'undefined') var util = {};
util.text = {};

util.text.EXPORT_OK	= [ 
	'wrap_on_space',
];
util.text.EXPORT_TAGS	= { ':all' : util.text.EXPORT_OK };

util.text.wrap_on_space = function( text, length ) {
	try {
		if (text.length <= length) return [ text, '' ];

		var truncated_text = text.substr(0,length);

		var pivot_pos = truncated_text.lastIndexOf(' ');

		return [ text.substr(0,pivot_pos).replace(/\s*$/,''), text.substr(pivot_pos+1) ];

	} catch(E) {
		alert('FIXME: util.text.wrap_on_space( "' + text + '", ' + length + ")");
		return [ text.substr(0,length), text.substr(length) ];
	}
}

dump('exiting util/text.js\n');

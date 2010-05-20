dump('entering util/text.js\n');

if (typeof util == 'undefined') var util = {};
util.text = {};

util.text.EXPORT_OK    = [ 
    'wrap_on_space', 'preserve_string_in_html',
];
util.text.EXPORT_TAGS    = { ':all' : util.text.EXPORT_OK };

util.text.wrap_on_space = function( text, length ) {
    try {

        if (String(text).length <= length) return [ text, '' ];

        var truncated_text = String(text).substr(0,length);

        var pivot_pos = truncated_text.lastIndexOf(' ');

        return [ text.substr(0,pivot_pos).replace(/\s*$/,''), String(text).substr(pivot_pos+1) ];

    } catch(E) {
        alert('FIXME: util.text.wrap_on_space( "' + text + '", ' + length + ")");
        return [ String(text).substr(0,length), String(text).substr(length) ];
    }
}

util.text.preserve_string_in_html = function( text ) {
    text = text.replace(/&/g,'&amp;');
    text = text.replace(/"/g,'&quot;');
    text = text.replace(/'/g,'&#39;');
    text = text.replace(/ /g,'&nbsp;');
    text = text.replace(/</g,'&lt;');
    text = text.replace(/>/g,'&gt;');
    return text;
}

util.text.reverse_preserve_string_in_html = function( text ) {
    text = text.replace(/&amp;/g, '&');
    text = text.replace(/&quot;/g, '"');
    text = text.replace(/&#39;/g, "'");
    text = text.replace(/&nbsp;/g, ' ');
    text = text.replace(/&lt;/g, '<');
    text = text.replace(/&gt;/g, '>');
    return text;
}

dump('exiting util/text.js\n');

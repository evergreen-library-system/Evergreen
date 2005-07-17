sdump('D_TRACE','Loading util.js\n');

var timer = {};
var counter = {};
var consider_Timeout_default = false;

function consider_Timeout( f, t, b) {
	sdump('D_TIMEOUT', arg_dump(arguments,{0:true,1:true,2:true}));
	if (b) {
		setTimeout(f,t);
	} else {
		if (consider_Timeout_default)
			setTimeout(f,t);
		else
			f();
	}
}

function merge_arrays() {
	var new_array = [];
	for (var i = 0; i < arguments.length; i++) {
		for (var j = 0; j < arguments[i].length; j++) {
			new_array.push( arguments[i][j] );
		}
	}
	return new_array;
}

function parse_render_string( obj_string, render_string, regexp ) {
	sdump('D_UTIL', arg_dump(arguments,{0:true,1:true}));
	var cmd;
	try {
		if (!regexp) regexp = /\$\$/g;
		if (render_string.slice(0,1) == '.') {
			cmd = obj_string + render_string;
		} else {
			cmd = render_string.replace( regexp, obj_string );
		}

	} catch(E) {

		sdump('D_ERROR',E);
	}
	sdump('D_UTIL', 'cmd = ' + cmd + '\n');
	return cmd;
}

function getString( key ) {
	var s = '';
	var bundles = document.getElementById('string_bundles');
	sdump('D_STRING','bundles = ' + bundles + ' bundles.childNodes.length = ' + bundles.childNodes.length + '\n');
	for (var i = 0; i < bundles.childNodes.length; i++) {
		var bundle = bundles.childNodes[i];
		sdump('D_STRING','\ttrying bundle = ' + bundle + '\n');
		try {

			var string = bundle.getString( key );
			if (string) {
				s = string;
				sdump('D_STRING','\tfound\n');
			} else {
				sdump('D_STRING','\tnot found\n');
			}

		} catch(E) {
			sdump('D_ERROR',E + '\n');
		}
	}
	sdump('D_STRING',key + '=' + s + '\n');
	return s;
}

function getFormattedString( key, strArray ) {
	var s = '';
	var bundles = document.getElementById('string_bundles');
	for (var i = i; i < bundles.childNodes.length; i++) {
		var bundle = bundles[i];
		try {

			var string = bundle.getFormattedString( key, strArray );
			if (string)
				s = string;

		} catch(E) {
			sdump('D_ERROR',E + '\n');
		}
	}
	sdump('D_STRING',key + '(' + strArray + ')=' + s + '\n');
	return s;
}

function string_to_array(s) {
	var my_array = [];
	for (var i = 0; i < s.length; i++ ) {
		my_array.push( s.charAt(i) );
	}
	return my_array;
}

function yesno(value) {
	switch(value) {
		case true: case 'true': case '1': case 'on':
			return 'Yes';
		default: 
			return 'No';
	}
}

function cents_as_dollars( cents ) {
	return '$' + cents.substr(0,cents.length-2) + '.' + cents.substr(cents.length - 2);
}

function formatted_date(date,format) {
	// pass in a Date object or epoch seconds
	if (typeof(date) == 'string') {
		date = new Date( parseInt( date + '000' ) );
	}
	var mm = date.getMonth() + 1;
	mm = mm.toString();
	if (mm.length == 1) mm = '0' +mm;
	var dd = date.getDate().toString();
	if (dd.length == 1) dd = '0' +dd;
	var yyyy = date.getFullYear().toString();
	var s = format.replace( /%m/g, mm );
	s = s.replace( /%d/g, dd );
	s = s.replace( /%Y/g, yyyy );
	return s;
}

function interval_to_seconds ( $interval ) {

        $interval = $interval.replace( /and/, ',' );
        $interval = $interval.replace( /,/, ' ' );

        var $amount = 0;
	var results = $interval.match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g);  
	for (var i in results) {
		var result = results[i].match( /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/ );
		if (result[2] == 's') $amount += result[1] ;
		if (result[2] == 'm') $amount += 60 * result[1] ;
		if (result[2] == 'h') $amount += 60 * 60 * result[1] ;
		if (result[2] == 'd') $amount += 60 * 60 * 24 * result[1] ;
		if (result[2] == 'w') $amount += 60 * 60 * 24 * 7 * result[1] ;
		if (result[2] == 'M') $amount += ((60 * 60 * 24 * 365)/12) * result[1] ;
		if (result[2] == 'y') $amount += 60 * 60 * 24 * 365 * result[1] ;
        }
        return $amount;
}

/*
function debug() {
	var s = '';
	for (var i = 0; i < arguments.length; i++) {
		s = s + arguments[i];
	}
	//sdump('D_UTIL','debug:' + s + '\n');
}
*/

function counter_init(id) {
	counter[id] = 0;
}

function counter_incr(id) {
	if (! counter[id]) { counter_init(id); }
	return ++counter[id];
}

function counter_peek(id) {
	if (! counter[id]) { return 0; }
	return counter[id];
}

function timer_init(id) {
	timer[id] = (new Date).getTime();
}

function timer_elapsed(id) {
	if (! timer[id]) { timer_init(id); }
	var ms = (new Date).getTime() - timer[id];
	return( ms + 'ms (' + ms/1000 + 's)' );
}

function dump_ns_node( node ) {
	return (
	'id=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.id.position] 
	+ '>  intra-id=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.intra_doc_id.position]
	+ '>  name=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.name.position]
	+ '>  node_type=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.type.position]
	+ '>  parent_node=<' + 
	node[fieldmap["Fieldmapper::biblio::record_node"].fields.parent_node.position]
	+ '>  '
	);
}

function nodeset2tree(ns) {
	for (var i in ns) {
		if (ns[i].parent_node) {
			ns_addChild( 
				ns, 
				ns[i].parent_node, 
				ns[i].intra_doc_id 
			);
		}
	}
	return ns;
}

function ns_addChild(ns,p,c) {
	if (! ns[p].children ) { ns[p].children = []; }
	ns[p].children.push(ns[c]);
}

function print_tabs(t) {
	var r = '';
	for (var j = 0; j < t; j++ ) { r = r + "\t"; }
	return r;
}

function pretty_print(s) {
	var r = ''; var t = 0;
	for (var i in s) {
		if (s[i] == '{') {
			r = r + "\n" + print_tabs(t) + s[i]; t++;
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == '[') {
			r = r + "\n" + print_tabs(t) + s[i]; t++;
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == '}') {
			t--; r = r + "\n" + print_tabs(t) + s[i]; 
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == ']') { 
			t--; r = r + "\n" + print_tabs(t) + s[i];
			r = r + "\n" + print_tabs(t);
		} else if (s[i] == ',') {
			r = r + s[i]; 
			r = r + "\n" + print_tabs(t);
		} else {
			r = r + s[i];
		}
	}
	return r;
}

function super_dump(o,t) {
	var s = "\n";
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "=-=-=\n";
	s = s + 'o.constructor == Array = ' + (o.constructor == Array) + '\n';
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "typeof = " + typeof(o) + "\n";
	try {
		var string = new XMLSerializer().serializeToString(o);
		return( string + "\n" );
	} catch( E ) {
		var i;
		var c = 0;
		for (i in o) {
			switch(typeof(i)) {
				case 'object':
					s = s + super_dump(i,t+1);
					break;
				default :
					var value = o[i];
					for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
					s = s + "\tMember#" + c++ + "\tType:" + typeof(value);
					if (typeof(value) == 'object') {
						value = super_dump(value,t+1);
					}
					s = s + "\ttoString:" + i.toString() + "\tvalue:" + value + "\n";
					break;
			}
		}
		return( s + "\n" );
	}
}

function super_dump_norecurse(o,t) {
	var s = "\n";
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "=-=-=\n";
	s = s + 'o.constructor == Array = ' + (o.constructor == Array) + '\n';
	for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
	s = s + "typeof = " + typeof(o) + "\n";
	try {
		var string = new XMLSerializer().serializeToString(o);
		return( string + "\n" );
	} catch( E ) {
		var i;
		var c = 0;
		for (i in o) {
			switch(typeof(i)) {
				default :
					var value = o[i];
					for (var ii = 0; ii < t; ii++) { s = s + '\t'; }
					s = s + "\tMember#" + c++ + "\tType:" + typeof(value);
					s = s + "\ttoString:" + i.toString() + "\n";
					break;
			}
		}
		return( s + "\n" );
	}
}



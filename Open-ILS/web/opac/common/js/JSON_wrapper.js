var JSON_CLASS_KEY	= '__c';
var JSON_DATA_KEY	= '__p';



function JSON_version() { return 'wrapper' }

function JSON2js(text) {
	return decodeJS(JSON2jsRaw(text));
}

function JSON2jsRaw(text) {
	var obj;
	eval( 'obj = ' + text );
	return obj;
}


/* iterates over object, arrays, or fieldmapper objects */
function jsIterate( arg, callback ) {
	if( arg && typeof arg == 'object' ) {
		if( arg.constructor == Array ) {
			for( var i = 0; i < arg.length; i++ ) 
				callback(arg, i);

		}  else if( arg.constructor == Object ) {
				for( var i in arg ) 
					callback(arg, i);

		} else if( arg._isfieldmapper && arg.a ) {
			for( var i = 0; i < arg.a.length; i++ ) 
				callback(arg.a, i);
		}
	}
}


/* removes the class/paylod wrapper objects */
function decodeJS(arg) {

	if(arg == null) return null;

	if(	arg && typeof arg == 'object' &&
			arg.constructor == Object &&
			arg[JSON_CLASS_KEY] ) {
		eval('arg = new ' + arg[JSON_CLASS_KEY] + '(arg[JSON_DATA_KEY])');	
	}

	jsIterate( arg, 
		function(o, i) {
			o[i] = decodeJS(o[i]);
		}
	);

	return arg;
}


function jsClone(obj) {
	if( obj == null ) return null;
	if( typeof obj != 'object' ) return obj;

	var newobj;
	if (obj.constructor == Array) {
		newobj = [];
		for( var i = 0; i < obj.length; i++ ) 
			newobj[i] = jsClone(obj[i]);

	} else if( obj.constructor == Object ) {
		newobj = {};
		for( var i in obj )
			newobj[i] = jsClone(obj[i]);

	} else if( obj._isfieldmapper && obj.a ) {
		eval('newobj = new '+obj.classname + '();');
		for( var i = 0; i < obj.a.length; i++ ) 
			newobj.a[i] = jsClone(obj.a[i]);
	}

	return newobj;
}
	

/* adds the class/paylod wrapper objects */
function encodeJS(arg) {
	if( arg == null ) return null;	
	if( typeof arg != 'object' ) return arg;

	if( arg._isfieldmapper ) {
      var newarr = []
      if(!arg.a) arg.a = [];
		for( var i = 0; i < arg.a.length; i++ ) 
			newarr[i] = encodeJS(arg.a[i]);

		var a = {};
		a[JSON_CLASS_KEY] = arg.classname;
		a[JSON_DATA_KEY] = newarr;
      return a;
	}

	var newobj;

   /*
   Array.prototype.__isarray = true;
	if(arg.__isarray) {
   */
	if(arg.length != undefined) {
		newobj = [];
		for( var i = 0; i < arg.length; i++ ) 
         newobj.push(encodeJS(arg[i]));
      return newobj;
	} 
   
	newobj = {};
	for( var i in arg )
		newobj[i] = encodeJS(arg[i]);
	return newobj;
}

/* turns a javascript object into a JSON string */
function js2JSON(arg) {
	return js2JSONRaw(encodeJS(arg));
}

function js2JSONRaw(arg) {

	if( arg == null ) 
		return 'null';

	var o;

	switch (typeof arg) {

		case 'object':

			if (arg.constructor == Array) {
				o = '';
				jsIterate( arg,
					function(obj, i) {
						if (o) o += ',';
						o += js2JSONRaw(obj[i]);
					}
				);
				return '[' + o + ']';

			} else if (typeof arg.toString != 'undefined') {
				o = '';
				jsIterate( arg,
					function(obj, i) {
						if (o) o += ',';
						o = o + js2JSONRaw(i) + ':' + js2JSONRaw(obj[i]);
					}
				);
				return '{' + o + '}';

			} else {
				return 'null';
			}

		case 'number': return arg;

		case 'string':
			var s = String(arg);
			s = s.replace(/\\/g, '\\\\');
			s = s.replace(/"/g, '\\"');
			s = s.replace(/\t/g, "\\t");
			s = s.replace(/\n/g, "\\n");
			s = s.replace(/\r/g, "\\r");
			s = s.replace(/\f/g, "\\f");
			return '"' + s + '"';

		default: return 'null';
	}
}


function __tabs(c) { 
	var s = ''; 
	for( i = 0; i < c; i++ ) s += '\t';
	return s;
}

function jsonPretty(str) {
	if(!str) return "";
	var s = '';
	var d = 0;
	for( var i = 0; i < str.length; i++ ) {
		var c = str.charAt(i);
		if( c == '{' || c == '[' ) {
			s += c + '\n' + __tabs(++d);
		} else if( c == '}' || c == ']' ) {
			s += '\n' + __tabs(--d) + '\n';
			if( str.charAt(i+1) == ',' ) {
				s += '\n' + __tabs(d);
			}
		} else if( c == ',' ) {
			s += ',\n' + __tabs(d);
		} else {
			s += c;
		}
	}
	return s;
}



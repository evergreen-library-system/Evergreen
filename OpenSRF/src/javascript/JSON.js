// in case we run on an implimentation that doesn't have "undefined";
var undefined;

function Cast (obj, class_constructor) {
	try {
		if (eval(class_constructor + '["_isfieldmapper"]')) {
			obj = eval("new " + class_constructor + "(obj)");
		}
	} catch( E ) {
		alert( E + "\n");
	} finally {
		return obj;
	}
}

function JSON2js (json) {

	json = String(json).replace( /\/\*--\s*S\w*?\s*?\s+\w+\s*--\*\//g, 'Cast(');
	json = String(json).replace( /\/\*--\s*E\w*?\s*?\s+(\w+)\s*--\*\//g, ', "$1")');

	var obj;
	if (json != '') {
		try {
			eval( 'obj = ' + json );
		} catch(E) {
			debug("Error building JSON object with string " + E + "\nString:\n" + json );
			return null;
		}
	}
	return obj;
}


function object2Array(obj) {
	if( obj == null ) return null;

	var arr = new Array();
	for( var i  = 0; i < obj.length; i++ ) {
		arr[i] = obj[i];
	}
	return arr;
}

function js2JSON(arg) {
	var i, o, u, v;

	try {
		switch (typeof arg) {
			case 'object':
	
				if(arg) {
	
					if (arg._isfieldmapper) { /* magi-c-ast for fieldmapper objects */
	
						if( arg.a.constructor != Array ) {
							var arr = new Array();
							for( var i  = 0; i < arg.a.length; i++ ) {
								if( arg.a[i] == null ) {
									arr[i] = null; continue;
								}
	
								if( typeof arg.a[i] != 'object' ) { 
									arr[i] = arg.a[i];
	
								} else if( typeof arg.a[i] == 'object' 
											&& arg.a[i]._isfieldmapper) {
	
									arr[i] = arg.a[i];
	
								} else {
									arr[i] = object2Array(arg.a[i]);		
								}
							}
							arg.a = arr;
						}
	
						return "/*--S " + arg.classname + " --*/" + js2JSON(arg.a) + "/*--E " + arg.classname + " --*/";
	
					} else {
	
						if (arg.constructor == Array) {
							o = '';
							for (i = 0; i < arg.length; ++i) {
								v = js2JSON(arg[i]);
								if (o) {
									o += ',';
								}
								if (v !== u) {
									o += v;
								} else {
									o += 'null';
								}
							}
							return '[' + o + ']';
	
						} else if (typeof arg.toString != 'undefined') {
							o = '';
							for (i in arg) {
								v = js2JSON(arg[i]);
								if (v !== u) {
									if (o) {
										o += ',';
									}
									o += js2JSON(i) + ':' + v;
								}
							}
	
							o = '{' + o + '}';
							return o;
	
						} else {
							return;
						}
					}
				}
				return 'null';
	
			case 'unknown':
			case 'number':
				return arg;
	
			case 'undefined':
			case 'function':
				return u;
	
			case 'string':
			default:
				return '"' + String(arg).replace(/(["\\])/g, '\\$1') + '"';
		}
	} catch(E) {
		if(arg && arg.toString) return arg.toString();
		return arg;
	}
}

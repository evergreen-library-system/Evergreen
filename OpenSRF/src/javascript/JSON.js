// in case we run on an implimentation that doesn't have "undefined";
var undefined;

function Cast (obj, class_constructor) {
	try {
		if (eval(class_constructor + '["_isfieldmapper"]')) {
			debug("Casting object to class " + class_constructor + "\n");
			obj = eval("new " + class_constructor + "(obj)");
			debug("My Classname: " + obj.classname);
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

	debug("=======================\n" + json);

	var obj;
	if (json != '') {
		try {
			eval( 'obj = ' + json );
		} catch(E) {
			debug("Error building JSON object with string " + json );
			return null;
		}
	}
	return obj;
}


function js2JSON(arg) {
	var i, o, u, v;

	debug( "Running js2JSON on " + arg );

	switch (typeof arg) {
		case 'object':

			if(arg) {

				if (arg._isfieldmapper) {
					return "/*--S acp*/" + js2JSON(arg.array) + "/*--E acp*/";

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
								o += 'null,';
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
						var obj_start = '{';
						var obj_end = '}';
						try {
							if ( arg.class_name() ) {
								obj_start = '/*--S ' + arg.class_name() + '--*/{';
								obj_end   = '}/*--E ' + arg.class_name() + '--*/';
							}
						} catch( E ) {}
						o = obj_start + o + obj_end;
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
}

// in case we run on an implimentation that doesn't have "undefined";
var undefined;

function Cast (obj, class_constructor) {
	try {
		if (eval(class_constructor + '.prototype["class_name"]')) {
			var template = eval("new " + class_constructor + "()");
			// copy the methods over to 'obj'
			for (var m in obj) {
				if (typeof(obj[m]) != 'undefined') {
					template[m] = obj[m];
				}
			}
			obj = template;
		}
	} catch( E ) {
		obj['class_name'] = function () { return class_constructor };
		//dump( super_dump(E) + "\n");
	} finally {
		return obj;
	}
}

function JSON2js (json) {
	json = json.replace( /\/\*--\s*S\w*?\s*?\s+\w+\s*--\*\//g, 'Cast(');
	json = json.replace( /\/\*--\s*E\w*?\s*?\s+(\w+)\s*--\*\//g, ', "$1")');
	var obj;
	if (json != '') {
		eval( 'obj = ' + json );
	}
	obj.toString = function () { return js2JSON(this) };
	return obj;
}

function js2JSON(arg) {
var i, o, u, v;

	switch (typeof arg) {
		case 'object':
			if (arg) {
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
			return 'null';
		case 'unknown':
		case 'undefined':
		case 'function':
			return u;
		case 'string':
		default:
			return '"' + String(arg).replace(/(["\\])/g, '\\$1') + '"';
	}
}

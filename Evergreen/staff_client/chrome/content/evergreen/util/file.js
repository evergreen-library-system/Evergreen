sdump('D_TRACE','Loading file.js\n');

var dirService = Components.classes["@mozilla.org/file/directory_service;1"].
	getService( Components.interfaces.nsIProperties );

//////////////////////////////////////////////////////////////////////////////////////////////////////

function set_object_in_file(file,obj) {
	try {
		if (obj) {
			if (typeof(file)=='string') file = get_file( file );
			var f = create_output_stream(file);
			var obj_json = js2JSON( obj );
			f.write( obj_json, String( obj_json ).length ); f.close();
		} else {
			throw('Tried setting obj = ' + obj + '\n');
		}
	} catch(E) {
		sdump('D_FILE', 'set_object_in_file: ' + js2JSON(E) + '\n');
		throw(E);
	}
}

function get_object_in_file(file) {
	try {
		if (typeof(file)=='string') file = get_file( file );
		if (file.exists()) {
	                var f = create_input_stream(file);
			var data = f.read(-1);
			var obj = JSON2js( data );
			f.close();
			return obj;
		} else {
			throw('File does not exist. ');
		}
	} catch(E) {
		sdump('D_FILE', 'get_object_in_file: ' + js2JSON(E) + '\n');
		throw(E);
	}
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

function create_input_stream(file) {
	try {
		if (typeof(file)=='string') file = get_file( file );
		var f = Components.classes["@mozilla.org/network/file-input-stream;1"]
			.createInstance(Components.interfaces.nsIFileInputStream);
		if (file && file.exists()) {
			f.init(file, 0x01, 0, 0);
			var s = Components.classes["@mozilla.org/scriptableinputstream;1"]
				.createInstance(Components.interfaces.nsIScriptableInputStream);
			if (f) {
				s.init(f);
				return s;
			}
		}
	} catch(E) {
		sdump('D_ERROR', E);
	}
	return null;
}

function create_output_stream(file) {
	try {
		if (typeof(file)=='string') file = get_file( file );
		var f = Components.classes["@mozilla.org/network/file-output-stream;1"]
			.createInstance(Components.interfaces.nsIFileOutputStream);
		if (file) {
			if (! file.exists()) file.create( 0, 0640 );
			f.init(file, 0x02 | 0x08 | 0x20, 0644, 0);
			return f;
		}
	} catch(E) {
		sdump('D_ERROR', E);
	}
	return null;
}

function get_file( fname ) {
	try {
		file = dirService.get( "AChrom",  Components.interfaces.nsIFile );
		file.append(mw.myPackageDir); file.append("content"); file.append("conf"); file.append(fname);
		sdump('D_FILE','get_file( ' + fname + ').path = ' + file.path + '\n');
		return file;
	} catch(E) {
		sdump('D_ERROR', E);
		return null;
	}
}

dump('entering util/file.js\n');

if (typeof util == 'undefined') util = {};
util.file = function (fname) {

	JSAN.use('util.error'); this.error = new util.error();

	this.dirService = Components.classes["@mozilla.org/file/directory_service;1"].
		getService( Components.interfaces.nsIProperties );

	if (fname) this.get(fname);

	return this;
};

util.file.prototype = {

	'myPackageDir' : 'evergreen',

	'name' : '',
	'_file' : null,
	'_input_stream' : null,
	'_output_stream' : null,

	'get' : function( fname ) {
		try {
			if (!fname) { fname = this.name; } else { this.name = fname; }
			if (!fname) throw('Must specify a filename.');

			this._file = this.dirService.get( "AChrom",  Components.interfaces.nsIFile );
			this._file.append(myPackageDir); 
			this._file.append("content"); 
			this._file.append("conf"); 
			this._file.append(fname);
	
			this.error.sdump('D_FILE',this._file.path);

			return this._file;

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.get(): ' + E);
			throw(E);
		}
	},

	'close' : function() {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (this._input_stream) { this._input_stream.close(); this._input_stream = null; }
			if (this._output_stream) { this._output_stream.close(); this._output_stream = null; }

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.close(): ' + E);
			throw(E);
		}
	},

	'set_object' : function(obj) {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (this._input_stream || this._output_stream) throw('Must .close() first.');
			if (!obj) throw('Must specify an object.');

			var obj_json; 
			try { obj_json = js2JSON( obj ); } catch(E) { throw('Could not JSONify the object: ' + E); }

			this._create_output_stream();
			this._output_stream.write( obj_json, String( obj_json ).length );
			this.close();

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.set_object(): ' + E);
			throw(E);
		}
	},

	'get_object' : function() {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (!this._file.exists()) throw('File does not exist.');
			if (this._input_stream || this._output_stream) throw('Must .close() first.');
			
			this._create_input_stream();
			var data = this._input_stream.read(-1);
			this.close();
	
			var obj; try { obj = JSON2js( data ); } catch(E) { throw('Could not js-ify the JSON: '+E); }
	
			return obj;

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.get_object(): ' + E);
			throw(E);
		}
	},

	'_create_input_stream' : function() {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (this._input_stream || this._output_stream) throw('Must .close() first.');
			if (!this._file.exists()) throw('File does not exist.');
	
			var f = Components.classes["@mozilla.org/network/file-input-stream;1"]
				.createInstance(Components.interfaces.nsIFileInputStream);
			f.init(this._file, 0x01, 0, 0);
			this._input_stream = Components.classes["@mozilla.org/scriptableinputstream;1"]
				.createInstance(Components.interfaces.nsIScriptableInputStream);
			if (f) {
				this._input_stream.init(f);
				return this._input_stream;
			} else {
				throw('Could not instantiate input stream.');
			}

		} catch(E) {
			this.error.sdump('D_ERROR','util.file._create_input_stream(): ' + E);
			throw(E);
		}
	},

	'_create_output_stream' : function() {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (this._input_stream || this._output_stream) throw('Must .close() first.');

			if (! this._file.exists()) this._file.create( 0, 0640 );

			this._output_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
				.createInstance(Components.interfaces.nsIFileOutputStream);
			this._output_stream.init(this._file, 0x02 | 0x08 | 0x20, 0644, 0);

			return this._output_stream;

		} catch(E) {
			this.error.sdump('D_ERROR','util.file._create_output_stream(): ' + E);
			throw(E);
		}
	}

}

dump('exiting util/file.js\n');

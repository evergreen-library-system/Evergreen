dump('entering util/file.js\n');

if (typeof util == 'undefined') util = {};
util.file = function (fname) {

	netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead");

	JSAN.use('util.error'); this.error = new util.error();

	this.dirService = Components.classes["@mozilla.org/file/directory_service;1"].
		getService( Components.interfaces.nsIProperties );

	if (fname) this.get(fname);

	return this;
};

util.file.prototype = {

	'myPackageDir' : 'open_ils_staff_client',

	'name' : '',
	'_file' : null,
	'_input_stream' : null,
	'_output_stream' : null,

	'get' : function( fname, path ) {
		try {
			if (!fname) { fname = this.name; } else { this.name = fname; }
			if (!fname) throw('Must specify a filename.');

			switch(path) {
				case 'profile' :
					this._file = this.dirService.get( "UChrom",  Components.interfaces.nsIFile );
					//this._file = this.dirService.get( "ProfD",  Components.interfaces.nsIFile );
				break;
				case 'chrome' : 
				default:
					this._file = this.dirService.get( "AChrom",  Components.interfaces.nsIFile );
					this._file.append(myPackageDir); 
					this._file.append("content"); 
					this._file.append("conf"); 
				break;
			}
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
			if (this._istream) { this._istream.close(); this._istream = null; }
			if (this._f) { this._f = null; }

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.close(): ' + E);
			throw(E);
		}
	},

	'append_object' : function(obj) {
		try {
			this.write_object('append',obj);
		} catch(E) {
			this.error.sdump('D_ERROR','util.file.append_object(): ' + E);
			throw(E);
		}
	},

	'set_object' : function(obj) {
		try {
			this.write_object('truncate',obj);
			this.close();
		} catch(E) {
			this.error.sdump('D_ERROR','util.file.set_object(): ' + E);
			throw(E);
		}
	},

	'write_object' : function(write_type,obj) {
		try {
			if (!this._file) throw('Must .get() a file first.');
			if (!obj) throw('Must specify an object.');

			var obj_json; 
			try { obj_json = js2JSON( obj ) + '\n'; } catch(E) { throw('Could not JSONify the object: ' + E); }

			this.write_content(write_type,obj_json);

		} catch(E) {
			this.error.sdump('D_ERROR','util.file.write_object(): ' + E);
			throw(E);
		}
	},

	'write_content' : function(write_type,content) {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead");
			if (!this._output_stream) this._create_output_stream(write_type);
			this._output_stream.write( content, String( content ).length );
		} catch(E) {
			this.error.sdump('D_ERROR','util.file.write_content(): ' + E);
			dump('write_type = ' + write_type + '\n');
			dump('content = ' + content + '\n');
			throw(E);
		}
	},

	'get_object' : function() {
		try {
			var data = this.get_content();
			var obj; try { obj = JSON2js( data ); } catch(E) { throw('Could not js-ify the JSON: '+E); }
			return obj;
		} catch(E) {
			this.error.sdump('D_ERROR','util.file.get_object(): ' + E);
			throw(E);
		}
	},

	'get_content' : function() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead");

			if (!this._file) throw('Must .get() a file first.');
			if (!this._file.exists()) throw('File does not exist.');
			
			if (!this._input_stream) this._create_input_stream();
			var data = this._input_stream.read(-1);
			//var data = {}; this._istream.readLine(data);
			return data;
		} catch(E) {
			this.error.sdump('D_ERROR','util.file.get_content(): ' + E);
			throw(E);
		}
	},

	'_create_input_stream' : function() {
		try {
			dump('_create_input_stream()\n');
			
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead");

			if (!this._file) throw('Must .get() a file first.');
			if (!this._file.exists()) throw('File does not exist.');

			this._f = Components.classes["@mozilla.org/network/file-input-stream;1"]
				.createInstance(Components.interfaces.nsIFileInputStream);
			this._f.init(this._file, 0x01, 0, 0);
			/*
			this._f.QueryInterface(Components.interfaces.nsILineInputStream);
			this._istream = this._f;
			*/
			this._input_stream = Components.classes["@mozilla.org/scriptableinputstream;1"]
				.createInstance(Components.interfaces.nsIScriptableInputStream);
			if (this._f) {
				this._input_stream.init(this._f);
			} else {
				throw('Could not instantiate input stream.');
			}
			return this._input_stream;

		} catch(E) {
			this.error.sdump('D_ERROR','util.file._create_input_stream(): ' + E);
			throw(E);
		}
	},

	'_create_output_stream' : function(param) {
		try {
			dump('_create_output_stream('+param+')\n');
			
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead");

			if (!this._file) throw('Must .get() a file first.');

			if (! this._file.exists()) this._file.create( 0, 0640 );

			this._output_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
				.createInstance(Components.interfaces.nsIFileOutputStream);
			switch(param){
				case 'append' :
					this._output_stream.init(this._file, 0x02 | 0x08 | 0x10 | 0x40, 0644, 0);
				break;
				case 'truncate' :
				default:
					this._output_stream.init(this._file, 0x02 | 0x08 | 0x20 | 0x40, 0644, 0);
				break;
			}

			return this._output_stream;

		} catch(E) {
			this.error.sdump('D_ERROR','util.file._create_output_stream(): ' + E);
			throw(E);
		}
	}

}

dump('exiting util/file.js\n');

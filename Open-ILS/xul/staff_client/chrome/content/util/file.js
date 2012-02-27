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

    'myPackageDir' : 'open_ils_staff_client',

    'name' : '',
    '_file' : null,
    '_input_stream' : null,
    '_output_stream' : null,

    'get' : function( fname, path ) {
        try {
            if (!fname) { fname = this.name; } else { this.name = fname; }
            if (!fname) throw('Must specify a filename.');

            try {
                var pref = Components.classes["@mozilla.org/preferences-service;1"]
                    .getService(Components.interfaces.nsIPrefBranch);
                if (!path && pref.getBoolPref("open-ils.write_in_user_chrome_directory")) path = 'uchrome';
            } catch(E) {
                // getBoolPref throws an exception if "open-ils.write_in_user_chrome_directory" is not defined at all
                // in defaults/preferences/prefs.js
            }

            switch(path) {
                case 'uchrome' :
                    this._file = this.dirService.get( "UChrm",  Components.interfaces.nsIFile );
                    //this._file = this.dirService.get( "ProfD",  Components.interfaces.nsIFile );
                break;
                default:
                case 'chrome' : 
                    this._file = this.dirService.get( "AChrom",  Components.interfaces.nsIFile );
                    this._file.append(myPackageDir); 
                    this._file.append("content"); 
                    this._file.append("conf"); 
                break;
            }
            this._file.append(fname);
    
            dump('file: ' + this._file.path + '\n');
            this.error.sdump('D_FILE',this._file.path);

            return this._file;

        } catch(E) {
            this.error.standard_unexpected_error_alert('error in util.file.get('+fname+','+path+')',E);
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
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.close(): ' + E);
            throw(E);
        }
    },

    'append_object' : function(obj) {
        try {
            this.write_object('append',obj);
        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.append_object(): ' + E);
            throw(E);
        }
    },

    'set_object' : function(obj) {
        try {
            this.write_object('truncate',obj);
            this.close();
        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.set_object(): ' + E);
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
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.write_object(): ' + E);
            throw(E);
        }
    },

    'write_content' : function(write_type,content) {
        try {
            if (!this._output_stream) this._create_output_stream(write_type);
            this._output_stream.write( content, String( content ).length );
        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.write_content(): ' + E);
            //dump('write_type = ' + write_type + '\n');
            //dump('content = ' + content + '\n');
            throw(E);
        }
    },

    'get_object' : function() {
        try {
            var data = this.get_content();
            var obj; try { obj = JSON2js( data ); } catch(E) { throw('Could not js-ify the JSON: '+E); }
            return obj;
        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.get_object(): ' + E);
            throw(E);
        }
    },

    'get_content' : function() {
        try {
            if (!this._file) throw('Must .get() a file first.');
            if (!this._file.exists()) throw('File does not exist.');
            
            if (!this._input_stream) this._create_input_stream();
            var data = this._input_stream.read(-1);
            //var data = {}; this._istream.readLine(data);
            return data;
        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file.get_content(): ' + E);
            throw(E);
        }
    },

    '_create_input_stream' : function() {
        try {
            //dump('_create_input_stream()\n');
            
            if (!this._file) throw('Must .get() a file first.');
            if (!this._file.exists()) throw('File does not exist.');

            this._f = Components.classes["@mozilla.org/network/file-input-stream;1"]
                .createInstance(Components.interfaces.nsIFileInputStream);
            this._f.init(this._file, MODE_RDONLY, 0, 0);
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
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file._create_input_stream(): ' + E);
            throw(E);
        }
    },

    '_create_output_stream' : function(param) {
        try {
            //dump('_create_output_stream('+param+') for '+this._file.path+'\n');
            
            if (!this._file) throw('Must .get() a file first.');

            if (! this._file.exists()) {
                if (param == 'truncate+exec') {
                    this._file.create( 0, 0777 );
                } else {
                    this._file.create( 0, PERMS_FILE );
                }
            }
            this._output_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
                .createInstance(Components.interfaces.nsIFileOutputStream);
            switch(param){
                case 'append' :
                    this._output_stream.init(this._file, MODE_WRONLY | MODE_APPEND, PERMS_FILE, 0);
                break;
                case 'truncate+exec' :
                    this._output_stream.init(this._file, MODE_WRONLY | MODE_CREATE | MODE_TRUNCATE, PERMS_FILE, 0);
                break;
                case 'truncate' :
                default:
                    this._output_stream.init(this._file, MODE_WRONLY | MODE_CREATE | MODE_TRUNCATE, PERMS_FILE, 0);
                break;
            }

            return this._output_stream;

        } catch(E) {
            this.error.sdump('D_ERROR',this._file.path + '\nutil.file._create_output_stream(): ' + E);
            throw(E);
        }
    },

    'pick_file' : function(params) {
        try {
            if (typeof params == 'undefined') params = {};
            if (typeof params.mode == 'undefined') params.mode = 'open';
            var nsIFilePicker = Components.interfaces.nsIFilePicker;
            var fp = Components.classes["@mozilla.org/filepicker;1"].createInstance( nsIFilePicker );
            fp.init( 
                window, 
                typeof params.title == 'undefined' ? params.mode : params.title,
                params.mode == 'open' ? nsIFilePicker.modeOpen : nsIFilePicker.modeSave
            );
            if (params.defaultFileName) {
                fp.defaultString = params.defaultFileName;
            }
            fp.appendFilters( nsIFilePicker.filterAll );
            var fp_result = fp.show();
            if ( ( fp_result == nsIFilePicker.returnOK || fp_result == nsIFilePicker.returnReplace ) && fp.file ) {
                return fp.file;
            } else {
                return null;
            }
        } catch(E) {
            this.error.standard_unexpected_error_alert('error picking file',E);
        }
    },

    'export_file' : function(params) {
        try {
            var obj = this;
            if (typeof params == 'undefined') params = {};
            params.mode = 'save';
            if (typeof params.data == 'undefined') throw('Need a .data field to export');
            var f = obj.pick_file( params );
            if (f) {
                obj._file = f;
                var temp = params.data;
                if (typeof params.not_json == 'undefined') {
                    temp = js2JSON( temp );
                }
                obj.write_content( 'truncate', temp );
                obj.close();
                alert('Exported ' + f.leafName);
                return obj._file;
            } else {
                alert('File not chosen for export.');
                return null;
            }

        } catch(E) {
            this.error.standard_unexpected_error_alert('Error exporting file',E);
                return null;
        }
    },

    'import_file' : function(params) {
        try {
            var obj = this;
            if (typeof params == 'undefined') params = {};
            params.mode = 'open';
            var f = obj.pick_file(params);
            if (f && f.exists()) {
                obj._file = f;
                var temp = obj.get_content();
                obj.close();
                if (typeof params.not_json == 'undefined') {
                    temp = JSON2js( obj.get_content() );
                }
                return temp;
            } else {
                alert('File not chosen for import.');
                return null;
            }
        } catch(E) {
            this.error.standard_unexpected_error_alert('Error importing file',E);
            return null;
        }
    }

}

dump('exiting util/file.js\n');

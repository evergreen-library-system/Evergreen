/** @file oils_config.js
  * Config code and Logger code
  * The config module is simple.  It parses an xml config file and 
  * the values from the file are accessed via XPATH queries.
  */

/** Searches up from Mozilla's chrome directory for the client 
  * config file and returns the file object
  */
function get_config_file() {

	var dirService = Components.classes["@mozilla.org/file/directory_service;1"].
		getService( Components.interfaces.nsIProperties );

	chromeDir = dirService.get( "AChrom",  Components.interfaces.nsIFile );
	chromeDir.append("evergreen");
	chromeDir.append("content");
	chromeDir.append("conf");
	chromeDir.append("client_config.xml");
	return chromeDir;

}


/** Constructor. You may provide an optional path to the config file. **/
function Config( config_file ) {

	if( Config.config != null ) { return Config.config; }

	config_file = get_config_file();

	// ------------------------------------------------------------------
	// Grab the data from the config file
	// ------------------------------------------------------------------
	var data = "";
	var fstream = Components.classes["@mozilla.org/network/file-input-stream;1"]
			.createInstance(Components.interfaces.nsIFileInputStream);

	var sstream = Components.classes["@mozilla.org/scriptableinputstream;1"]
			.createInstance(Components.interfaces.nsIScriptableInputStream);

	fstream.init(config_file, 1, 0, false);
	sstream.init(fstream);
	data += sstream.read(-1);

	sstream.close();
	fstream.close();
	
	

	var DOMParser = new Components.Constructor(
		"@mozilla.org/xmlextras/domparser;1", "nsIDOMParser" );

	this.config_doc = new DOMParser().parseFromString( data, "text/xml" );

	Config.config = this;

}

/** Returns the value stored in the config file found with the
  * given xpath expression
  * E.g.  config.get_value( "/oils_config/dirs/log_dir" );
  * Note, the 'oils_config' node is the base of the xpath expression,
  * so something like this will also work:
  * config.get_value( "dirs/log_dir" );
  */
Config.prototype.get_value = function( xpath_query ) {

	var evaluator = Components.classes["@mozilla.org/dom/xpath-evaluator;1"].
		createInstance( Components.interfaces.nsIDOMXPathEvaluator );

	var xpath_obj = evaluator.evaluate( xpath_query, this.config_doc.documentElement, null, 0, null );
	if( ! xpath_obj ) { return null; }

	var node = xpath_obj.iterateNext();
	if( node == null ) {
		throw new oils_ex_config( "No config option matching " + xpath_query );
	}

	return node.firstChild.nodeValue;
}	






// ------------------------------------------------------------------
// Logger code.
// ------------------------------------------------------------------
/** The global logging object */
Logger.logger		= null;
/** No logging level */
Logger.NONE			= 0;
/** Error log level */
Logger.ERROR		= 1;
/** Info log level */
Logger.INFO			= 2;
/* Debug log level */
Logger.DEBUG		= 3;

/** There exists a single logger object that all components share.
  * Calling var logger = new Logger() will return the same one
  * with each call.  This is so we only need one file handle for
  * each type of log file.
  */
function Logger() {

	if( Logger.logger != null ) { return Logger.logger }

	var config = new Config();
	this.log_level = config.get_value( "system/log_level" );

	this.stdout_log = config.get_value( "system/stdout_log" );

	if( ! this.stdout_log || this.stdout_log < 0 || this.stdout_log > 2 ) {
		throw new oils_ex_config( "stdout_log setting is invalid: " + this.stdout_log + 
				". Should be 0, 1, or 2." );
	}

	// ------------------------------------------------------------------
	// Load up all of the log files
	// ------------------------------------------------------------------
	var transport_file = config.get_value( "logs/transport" );
	if( transport_file == null ) {
		throw new oils_ex_config( "Unable to load transport log file: 'logs/transport'" );
	}

	var debug_file = config.get_value( "logs/debug" );
	if( debug_file == null ) {
		throw new oils_ex_config( "Unable to load debug log file: 'logs/debug'" );
	}
	
	var error_file = config.get_value( "logs/error" );
	if( error_file == null ) {
		throw new oils_ex_config( "Unable to load debug log file: 'logs/error'" );
	}


	// ------------------------------------------------------------------
	// Build the file objects
	// ------------------------------------------------------------------
	var transport_file_obj = Logger.get_log_file( transport_file );

	var debug_file_obj = Logger.get_log_file( debug_file );

	var error_file_obj = Logger.get_log_file( error_file );


	// ------------------------------------------------------------------
	// Build all of the file stream objects
	// ------------------------------------------------------------------
	this.transport_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
			.createInstance(Components.interfaces.nsIFileOutputStream);

	this.debug_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
			.createInstance(Components.interfaces.nsIFileOutputStream);

	this.error_stream = Components.classes["@mozilla.org/network/file-output-stream;1"]
			.createInstance(Components.interfaces.nsIFileOutputStream);

	// ------------------------------------------------------------------
	// Init all of the streams
	// use 0x02 | 0x10 to open file for appending.
	// ------------------------------------------------------------------
	this.transport_stream.init(transport_file_obj,	0x02 | 0x10 | 0x08, 0664, 0 ); 
	this.debug_stream.init(	debug_file_obj,			0x02 | 0x10 | 0x08, 0664, 0 ); 
	this.error_stream.init(	error_file_obj,			0x02 | 0x10 | 0x08, 0664, 0 ); 

	Logger.logger = this;

}

/** Internal.  Returns a XPCOM nsIFile object for the log file we're interested in */
Logger.get_log_file = function( log_name ) {

	var dirService = Components.classes["@mozilla.org/file/directory_service;1"].
		getService( Components.interfaces.nsIProperties );

	logFile = dirService.get( "AChrom",  Components.interfaces.nsIFile );
	logFile.append("evergreen");
	logFile.append("content");
	logFile.append("log");
	logFile.append( log_name );

	if( ! logFile.exists() ) {
		logFile.create( 0, 0640 );
	}

	return logFile;
}



/** Internal. Builds a log message complete with data, etc. */
Logger.prototype.build_string = function( message, level ) {

	if( ! (message && level) ) { return null; }

	var lev = "INFO";
	if( level == Logger.ERROR ) { lev = "ERROR"; }
	if( level == Logger.DEBUG ) { lev = "DEBUG"; }

	var date		= new Date();
	var year		= date.getYear();
	year += 1900;

	var month	= ""+date.getMonth();
	if(month.length==1) {month="0"+month;}
	var day		= ""+date.getDate();
	if(day.length==1) {day="0"+day;}
	var hour		= ""+date.getHours();
	if(hour.length== 1){hour="0"+hour;}
	var min		= ""+date.getMinutes();
	if(min.length==1){min="0"+min;}
	var sec		= ""+date.getSeconds();
	if(sec.length==1){sec="0"+sec;}
	var mil		= ""+date.getMilliseconds();
	if(mil.length==1){sec="0"+sec;}

	var date_string = year + "-" + month + "-" + day + " " + 
		hour + ":" + min + ":" + sec + "." + mil;

	var str_array = message.split('\n');
	var ret_array = new Array();
	for( var i in str_array ) {
		ret_str = "[" + date_string +  "] " + lev + " " + str_array[i] + "\n";
		ret_array.push( ret_str );
	}

	var line = "-------------------------\n";
	ret_array.unshift( line );

	return ret_array;
}

/** Internal. Does the actual writing */
Logger.prototype._log = function( data, stream, level ) {

	if( ! data ) { return; }
	if( ! stream ) { 
		throw oils_ex_logger( "No file stream open for log message: " + data ); 
	}
	if( ! level ) { level = Logger.DEBUG; }

	if( level > this.log_level ) { return; }
	var str_array = this.build_string( data, level );
	if( ! str_array ) { return; }

	for( var i in str_array ) {
		if( this.stdout_log > 0 ) { dump( str_array[i] ); }
		if( this.stdout_log < 2 ) { stream.write( str_array[i], str_array[i].length ); }
	}

	// write errors to the error log if they were destined for anywhere else
	if( level == Logger.ERROR && stream != this.error_stream ) {
		for( var i in str_array ) {
			if( this.stdout_log > 0 ) { dump( str_array[i] ); }
			if( this.stdout_log < 2 ) { this.error_stream.write( str_array[i], str_array[i].length ); }
		}
	}
}
	


/** Writes the message to the error log */
Logger.prototype.error = function( message, level ) {
	this._log( message, this.error_stream, level );
}


/** Writes to the debug log */
Logger.prototype.debug = function( message, level ) {
	this._log( message, this.debug_stream, level );
}


/** Writes to the transport log */
Logger.prototype.transport = function( message, level ) {
	this._log( message, this.transport_stream, level );
}

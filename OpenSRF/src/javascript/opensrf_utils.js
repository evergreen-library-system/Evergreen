// ------------------------------------------------------------------
// Houses utility functions
// ------------------------------------------------------------------

/** Prints to console.  If alert_bool = true, displays a popup as well */
function _debug( message, alert_bool ) {

	dump( "\n" + new Date() + "\n--------------------------------\n" + 
			message + "\n-----------------------------------\n" );
	if( alert_bool == true ) { alert( message ) };

}


/** Provides millisec sleep times, enjoy... */
function sleep(gap){ 

	var threadService = Components.classes["@mozilla.org/thread;1"].
		getService(Components.interfaces.nsIThread);

	var th = threadService.currentThread;
	th.sleep(gap);
}



/** Top level exception classe */
function oils_ex() {}

/** Initializes an exception */
oils_ex.prototype.init_ex = function( name, message ) {
	if( !(name && message) ) { return; }
	this.name = name;
	this.message = name + " : " + message;
	new Logger().debug( "***\n" + this.message + "\n***", Logger.ERROR );
}

/** Returns a string representation of an exception */
oils_ex.prototype.toString = function() {
	return this.message;
}


oils_ex_transport.prototype = new oils_ex();
oils_ex_transport.prototype.constructor = oils_ex_transport;
oils_ex_transport.baseClass = oils_ex.prototype.constructor;

/** Thrown when the transport connection has problems*/
function oils_ex_transport( message ) {
	this.init_ex( "Transport Exception", message );
}


oils_ex_transport_auth.prototype = new oils_ex_transport(); 
oils_ex_transport_auth.prototype.constructor = oils_ex_transport_auth;
oils_ex_transport_auth.baseClass = oils_ex_transport.prototype.constructor;

/** Thrown when the initial transport connection fails */
function oils_ex_transport_auth( message ) {
	this.init_ex( "Transport Authentication Error", message );
}

oils_ex_dom.prototype = new oils_ex(); 
oils_ex_dom.prototype.constructor = oils_ex_dom;
oils_ex_dom.baseClass = oils_ex.prototype.constructor;

/** Thrown when there is an XML problem */
function oils_ex_dom( message ) {
	this.init_ex( "DOM Error", message );
}

oils_ex_message.prototype = new oils_ex();
oils_ex_message.prototype.constructor = oils_ex_message;
oils_ex_message.baseClass = oils_ex.prototype.constructor;

/** Thrown when there is a message problem */
function oils_ex_message( message ) {
	this.init_ex( "OILS Message Layer Error", message ) ;
}

oils_ex_config.prototype = new oils_ex();
oils_ex_config.prototype.constructor = oils_ex_config;
oils_ex_config.prototype.baseClass = oils_ex.prototype.constructor;

/** Thrown when values cannot be retrieved from the config file */
function oils_ex_config( message ) {
	this.init_ex( "OILS Config Exception", message );
}

oils_ex_logger.prototype = new oils_ex();
oils_ex_logger.prototype.constructor = oils_ex_logger;
oils_ex_logger.prototype.baseClass = oils_ex.prototype.constructor;

/** Thrown where there are logging problems */
function oils_ex_logger( message ) {
	this.init_ex( "OILS Logger Exception", message );
}


oils_ex_args.prototype = new oils_ex();
oils_ex_args.prototype.constructor = oils_ex_args;
oils_ex_args.prototype.baseClass = oils_ex.prototype.constructor;

/** Thrown when when a method does not receive all of the required arguments */
function oils_ex_args( message ) {
	this.init_ex( "Method Argument Exception", message );
}


oils_ex_session.prototype = new oils_ex();
oils_ex_session.prototype.constructor = oils_ex_session;
oils_ex_session.prototype.baseClass = oils_ex.prototype.constructor;

/** Thrown where there is a session processing problem */
function oils_ex_session( message ) {
	this.init_ex( "Session Exception", message );
}

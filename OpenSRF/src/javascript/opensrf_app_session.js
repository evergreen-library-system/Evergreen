/** @file oils_app_session.js
  * @brief AppRequest and AppSession.
  * The AppSession class does most of the communication work and the AppRequest 
  * contains the top level client API.
  */

/** The default wait time when a client calls recv. It
  * may be overrided by passing in a value to the recv method
  */
AppRequest.DEF_RECV_TIMEOUT = 10000;

/** Provide a pre-built AppSession object and the payload of the REQUEST
  * message you wish to send
  */
function AppRequest( session, payload ) {

	/** Our controling session */
	this.session = session;

	/** This requests message thread trace */
	this.thread_trace = null;

	/** This request REQUEST payload */
	this.payload = payload;

	/** True if this request has completed is request cycle */
	this.is_complete = false;

	/** Stores responses received from requests */
	this.recv_queue = new Array();
}

/** returns true if this AppRequest has completed its request cycle.  */
AppRequest.prototype.complete = function() {
	if( this.is_complete ) { return true; }
	this.session.queue_wait(0);
	return this.is_complete;
}

/** When called on an AppRequest object, its status will be
  * set to complete regardless of its previous status
  */
AppRequest.prototype.set_complete = function() {
	this.is_complete = true;
}

/** Returns the current thread trace */
AppRequest.prototype.get_thread_trace = function() {
	return this.thread_trace;
}

/** Pushes some payload onto the recv queue */
AppRequest.prototype.push_queue = function( payload ) {
	this.recv_queue.push( payload );
}

/** Returns the current payload of this request */
AppRequest.prototype.get_payload = function() {
	return this.payload;
}

/** Removes this request from the our AppSession's request bucket 
  * Call this method when you are finished with a particular request 
  */
AppRequest.prototype.finish = function() {
	this.session.remove_request( this );
}


/** Retrieves the current thread trace from the associated AppSession object,
  * increments that session's thread trace, sets this AppRequest's thread trace
  * to the new value.  The request is then sent.
  */
AppRequest.prototype.make_request = function() {
	var tt = this.session.get_thread_trace();
	this.session.set_thread_trace( ++tt );
	this.thread_trace = tt;
	this.session.add_request( this );
	this.session.send( oilsMessage.REQUEST, tt, this.payload );
}

/** Checks the receive queue for message payloads.  If any are found, the first 
  * is returned.  Otherwise, this method will wait at most timeout seconds for
  * a message to appear in the receive queue.  Once it arrives it is returned.
  * If no messages arrive in the timeout provided, null is returned.

  * NOTE: timeout is in * milliseconds *
  */

AppRequest.prototype.recv = function( /*int*/ timeout ) {


	if( this.recv_queue.length > 0 ) {
		return this.recv_queue.shift();
	}

	if( this.is_complete ) { return null; }

	if( timeout == null ) {
		timeout = AppRequest.DEF_RECV_TIMEOUT;
	}

	while( timeout > 0 ) {

		var start = new Date().getTime();
		this.session.queue_wait( timeout );

		if( this.recv_queue.length > 0 ) {
			return this.recv_queue.shift();
		}

		// shortcircuit the call if we're already complete
		if( this.complete() ) { return null; }

		new Logger().debug( "AppRequest looping in recv " 
				+ this.get_thread_trace() + " with timeout " + timeout, Logger.DEBUG );

		var end = new Date().getTime();
		timeout -= ( end - start );
	}

	return null;
}

/** Resend this AppRequest's REQUEST message, useful for recovering
 * from disconnects, etc.
 */
AppRequest.prototype.resend = function() {

	new Logger().debug( "Resending msg with thread trace: " 
			+ this.get_thread_trace(), Logger.DEBUG );
	this.session.send( oilsMessage.REQUEST, this.get_thread_trace(), this.payload );
}



	
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// AppSession code
// -----------------------------------------------------------------------------

/** Global cach of AppSession objects */
AppSession.session_cache = new Array();

// -----------------------------------------------------------------------------
// Session states
// -----------------------------------------------------------------------------
/** True when we're attempting to connect to a remte service */
AppSession.CONNECTING	= 0; 
/** True when we have successfully connected to a remote service */
AppSession.CONNECTED		= 1;
/** True when we have been disconnected from a remote service */
AppSession.DISCONNECTED = 2;
/** The current default method protocol */
AppSession.PROTOCOL		= 1;

/** Our connection with the outside world */
AppSession.transport_handle = null;


/** Returns the session with the given session id */
AppSession.find_session = function(session_id) {
	return AppSession.session_cache[session_id];
}

/** Adds the given session to the global cache */
AppSession.push_session = function(session) {
	AppSession.session_cache[session.get_session_id()] = session;
}

/** Deletes the session with the given session id from the global cache */
AppSession.delete_session = function(session_id) {
	AppSession.session_cache[session_id] = null;
}

/** Builds a new session.
  * @param remote_service The remote service we want to make REQUEST's of
  */
function AppSession( remote_service ) {

	if (arguments.length == 3) {
		// it used to be AppSession( username, password, remote_service )
		remote_service = arguments[2];
	}

	/** Our logger object */
	this.logger = new Logger();

	random_num = Math.random() + "";
	random_num.replace( '.', '' );

	/** Our session id */
	this.session_id = new Date().getTime() + "" + random_num;

	//this.auth = new userAuth( username, password );

	/** Our AppRequest queue */
	this.request_queue = new Array();

	/** Our connectivity state */
	this.state = AppSession.DISCONNECTED;

	var config = new Config();
	
	/** The remote ID of the service we are communicating with as retrieved 
	  * from the config file
	 */
	this.orig_remote_id = config.get_value( "remote_service/" + remote_service );
	if( ! this.orig_remote_id ) { 
		throw new oils_ex_config( "No remote service id for: " + remote_service );
	}

	/** The current remote ID of the service we are communicating with */
	this.remote_id = this.orig_remote_id;

	/** Our current request threadtrace, which is incremented with each 
	  * newly sent AppRequest */
	this.thread_trace = 0;

	/** Our queue of AppRequest objects */
	this.req_queue = new Array();

	/** Our queue of AppRequests that are awaiting a resend of their payload */
	this.resend_queue = new Array();

	// Build the transport_handle if if doesn't already exist
	if( AppSession.transport_handle == null ) {
		this.build_transport();
	}

	AppSession.push_session( this );

}

/** The transport implementation is loaded from the config file and magically
  * eval'ed into an object.  All connection settings come from the client 
  * config.
  * * This should only be called by the AppSession constructor and only when
  * the transport_handle is null.
  */
AppSession.prototype.build_transport = function() {

	var config = new Config();
	var transport_impl = config.get_value( "transport/transport_impl" );
	if( ! transport_impl ) {
		throw new oils_ex_config( "No transport implementation defined in config file" );
	}

	var username	= config.get_value( "transport/username" );
	var password	= config.get_value( "transport/password" );
	var this_host	= config.get_value( "system/hostname" );
	var resource	= this_host + "_" + new Date().getTime();
	var server		= config.get_value( "transport/primary" );
	var port			= config.get_value( "transport/port" );
	var tim			= config.get_value( "transport/connect_timeout" );
	var timeout		= tim * 1000;

	var eval_string = 
		"AppSession.transport_handle = new " + transport_impl + "( username, password, resource );";

	eval( eval_string );
	
	if( AppSession.transport_handle == null ) {
		throw new oils_ex_config( "Transport implementation defined in config file is not valid" );
	}

	if( !AppSession.transport_handle.connect( server, port, timeout ) ) {
		throw new oils_ex_transport( "Connection attempt to remote service timed out" );
	}

	if( ! AppSession.transport_handle.connected() ) {
		throw new oils_ex_transport( "AppSession is unable to connect to the remote service" );
	}
}


/** Adds the given AppRequest object to this AppSession's request queue */
AppSession.prototype.add_request = function( req_obj ) {
	new Logger().debug( "Adding AppRequest: " + req_obj.get_thread_trace(), Logger.DEBUG );
	this.req_queue[req_obj.get_thread_trace()] = req_obj;
}

/** Removes the AppRequest object from this AppSession's request queue */
AppSession.prototype.remove_request = function( req_obj ) {
	this.req_queue[req_obj.get_thread_trace()] = null;
}

/** Returns the AppRequest with the given thread_trace */
AppSession.prototype.get_request = function( thread_trace ) {
	return this.req_queue[thread_trace];
}


/** Returns this AppSession's session id */
AppSession.prototype.get_session_id = function() { 
	return this.session_id; 
}

/** Resets the remote_id for the transport to the original remote_id retrieved
  * from the config file
  */
AppSession.prototype.reset_remote = function() { 
	this.remote_id = this.orig_remote_id; 
}

/** Returns the current message thread trace */
AppSession.prototype.get_thread_trace = function() {
	return this.thread_trace;
}

/** Sets the current thread trace */
AppSession.prototype.set_thread_trace = function( tt ) {
	this.thread_trace = tt;
}

/** Returns the state that this session is in (i.e. CONNECTED) */
AppSession.prototype.get_state = function() {
	return this.state;
}

/** Sets the session state.  The state should be one of the predefined 
  * session AppSession session states.
  */
AppSession.prototype.set_state = function(state) {
	this.state = state;
}

/** Returns the current remote_id for this session */
AppSession.prototype.get_remote_id = function() {
	return this.remote_id;
}

/** Sets the current remote_id for this session */
AppSession.prototype.set_remote_id = function( id ) {
	this.remote_id = id;
}

/** Pushes an AppRequest object onto the resend queue */
AppSession.prototype.push_resend = function( app_request ) {
	this.resend_queue.push( app_request );
}

/** Destroys the current session.  This will disconnect from the
  * remote service, remove all AppRequests from the request
  * queue, and finally remove this session from the global cache
  */
AppSession.prototype.destroy = function() {

	new Logger().debug( "Destroying AppSession: " + this.get_session_id(), Logger.DEBUG );

	// disconnect from the remote service
	if( this.get_state() != AppSession.DISCONNECTED ) {
		this.disconnect();
	}
	// remove us from the global cache
	AppSession.delete_session( this.get_session_id() );

	// Remove app request references
	for( var index in this.req_queue ) {
		this.req_queue[index] = null;
	}
}

/** This forces a resend of all AppRequests that are currently 
  * in the resend queue
  */
AppSession.prototype.flush_resend = function() {

	if( this.resend_queue.length > 0 ) {
		new Logger().debug( "Resending " 
			+ this.resend_queue.length + " messages", Logger.INFO );
	}

	var req = this.resend_queue.shift();

	while( req != null ) {
		req.resend();
		req = this.resend_queue.shift();
	}
}

/** This method tracks down the AppRequest with the given thread_trace and 
  * pushes the payload into that AppRequest's recieve queue.
  */
AppSession.prototype.push_queue = function( dom_payload, thread_trace ) {

	var req = this.get_request( thread_trace );
	if( ! req ) {
		new Logger().debug( "No AppRequest exists for TT: " + thread_trace, Logger.ERROR );
		return;
	}
	req.push_queue( dom_payload );
}


/** Connect to the remote service.  The connect timeout is read from the config.
  * This method returns null if the connection fails.  It returns a reference
  * to this AppSession object otherwise.
  */
AppSession.prototype.connect = function() {

	if( this.get_state() == AppSession.CONNECTED ) { 
		return this;
	}

	var config = new Config();
	var rem = config.get_value( "transport/connect_timeout" );
	if( ! rem ) {
		throw new oils_ex_config( "Unable to retreive timeout value from config" );
	}

	var remaining = rem * 1000; // milliseconds

	this.reset_remote();
	this.set_state( AppSession.CONNECTING );
	this.send( oilsMessage.CONNECT, 0, "" );

	new Logger().debug( "CONNECTING with timeout: " + remaining, Logger.DEBUG );

	while( this.get_state() != AppSession.CONNECTED && remaining > 0 ) {

		var starttime = new Date().getTime();
		this.queue_wait( remaining );
		var endtime = new Date().getTime();
		remaining -= (endtime - starttime);
	}

	if( ! this.get_state() == AppSession.CONNECTED ) {
		return null;
	}

	return this;
}

/** Disconnects from the remote service */
AppSession.prototype.disconnect = function() {

	if( this.get_state() == AppSession.DISCONNECTED ) {
		return;
	}

	this.send( oilsMessage.DISCONNECT, this.get_thread_trace(), "" );
	this.set_state( AppSession.DISCONNECTED );
	this.reset_remote();
}


/** Builds a new message with the given type and thread_trace.  If the message
  * is a REQUEST, then the payload is added as well.
  * This method will verify that the session is in the CONNECTED state before
  * sending any REQUEST's by attempting to do a connect.
  *
  * Note: msg_type and thread_trace must be provided.
  */
AppSession.prototype.send = function( msg_type, thread_trace, payload ) {

	if( msg_type == null || thread_trace == null ) {
		throw new oils_ex_args( "Not enough arguments provided to AppSession.send method" );
	}

	// go ahead and make sure there's nothing new to process
	this.queue_wait(0);

	var msg;
	msg = new oilsMessage( msg_type, AppSession.PROTOCOL );

	msg.setThreadTrace( thread_trace );

	if( msg_type == oilsMessage.REQUEST ) {
		if( ! payload ) {
			throw new oils_ex_args( "No payload provided for REQUEST message in AppSession.send" );
		}
		msg.add( payload );
	}


	// Make sure we're connected
	if( (msg_type != oilsMessage.DISCONNECT) && (msg_type != oilsMessage.CONNECT) &&
			(this.get_state() != AppSession.CONNECTED) ) {
		if( ! this.connect() ) {
			throw new oils_ex_session( this.get_session_id() + " | Unable to connect to remote service after redirect" );
		}
	}

	this.logger.debug( "AppSession sending tt: " 
			+ thread_trace + " to " + this.get_remote_id() 
			+ " " +  msg_type , Logger.INFO );

	AppSession.transport_handle.send( this.get_remote_id(), this.get_session_id(), msg.toString(true) );

}


/** Waits up to 'timeout' milliseconds for some data to arrive.
  * Any data that arrives will be process according to its
  * payload and message type.  This method will return after
  * any data has arrived.
  * @param timeout How many milliseconds to wait or data to arrive
  */
AppSession.prototype.queue_wait = function( timeout ) {
	this.flush_resend(); // necessary if running parallel sessions 
	new Logger().debug( "In queue_wait " + timeout, Logger.DEBUG );
	var tran_msg = AppSession.transport_handle.process_msg( timeout );
	this.flush_resend();
}




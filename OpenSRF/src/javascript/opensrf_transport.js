/** @file oils_transport.js
  * Houses the top level transport 'abstract' classes
  * You can think of this like a header file which provides the 
  * interface that any transport code must implement
  */


// ------------------------------------------------------------------
// TRANSPORT_CONNECTION

/** Constructor */
function transport_connection( username, password, resource ) { }

/** Connects to the transport host */
transport_connection.prototype.connect = function(  host, /*int*/ port, /*int*/ timeout ) {}

/** Sends a new message to recipient, with session_id and body */
transport_connection.prototype.send = function( recipient, session_id, body ) {}


/** Returns a transport_message.  This function will return 
  * immediately if there is a message available.  Otherwise, it will
  * wait at most 'timeout' seconds for one to arrive.  Returns
  * null if a message does not arrivae in time.

  * 'timeout' is specified in milliseconds
  */
transport_connection.prototype.recv = function( /*int*/ timeout ) {}

/** This method calls recv and then passes the contents on to the
  * message processing stack.
  */
transport_connection.prototype.process_msg = function( /*int*/ timeout ) {
	var msg = this.recv( timeout );
	if( msg ) { Transport.handler( msg ); }
}

/** Disconnects from the transpot host */
transport_connection.prototype.disconnect = function() {}

/** Returns true if this connection instance is currently connected
  * to the transport host.
  */
transport_connection.prototype.connected = function() {}



// ------------------------------------------------------------------
// TRANSPORT_MESSAGE
	

/** Constructor */
function transport_message( sender, recipient, session_id, body ) {}

/** Returns the sender of the message */
transport_message.prototype.get_sender = function() {}

/** Returns the session id */
transport_message.prototype.get_session = function() {}

/** Returns the message body */
transport_message.prototype.get_body = function() {}
	


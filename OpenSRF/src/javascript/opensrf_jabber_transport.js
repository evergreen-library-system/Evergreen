// ------------------------------------------------------------------
//		Houses the jabber transport code
//
// 1. jabber_connection - high level jabber component
// 2. jabber_message - message class
// 3. jabber_socket - socket handling code (shouldn't have to 
//		use this class directly)
//
// Requires oils_utils.js
// ------------------------------------------------------------------





// ------------------------------------------------------------------
// JABBER_CONNECTION
// High level transport code

// ------------------------------------------------------------------
// Constructor
// ------------------------------------------------------------------
jabber_connection.prototype = new transport_connection();
jabber_connection.prototype.constructor = jabber_connection;
jabber_connection.baseClass = transport_connection.prototype.constructor;

/** Initializes a jabber_connection object */
function jabber_connection( username, password, resource ) {

	this.username		= username;
	this.password		= password;
	this.resource		= resource;
	this.socket			= new jabber_socket();

	this.host			= "";

}

/** Connects to the Jabber server.  'timeout' is the connect timeout
  * in milliseconds 
 */
jabber_connection.prototype.connect = function( host, port, timeout ) {
	this.host = host;
	return this.socket.connect( 
			this.username, this.password, this.resource, host, port, timeout );
}

/** Sends a message to 'recipient' with the provided message 
  * thread and body 
  */
jabber_connection.prototype.send = function( recipient, thread, body ) {
	var jid = this.username+"@"+this.host+"/"+this.resource;
	var msg = new jabber_message( jid, recipient, thread, body );
	return this.socket.tcp_send( msg.to_string() );
}

/** This method will wait at most 'timeout' milliseconds
  * for a Jabber message to arrive.  If one arrives
  * it is returned to the caller, other it returns null
  */
jabber_connection.prototype.recv = function( timeout ) {
	return this.socket.recv( timeout );
}

/** Disconnects from the jabber server */
jabber_connection.prototype.disconnect = function() {
	return this.socket.disconnect();
}

/** Returns true if we are currently connected to the 
  * Jabber server
  */
jabber_connection.prototype.connected = function() {
	return this.socket.connected();
}



// ------------------------------------------------------------------
// JABBER_MESSAGE
// High level message handling code
	

jabber_message.prototype = new transport_message();
jabber_message.prototype.constructor = jabber_message;
jabber_message.prototype.baseClass = transport_message.prototype.constructor;

/** Builds a jabber_message object */
function jabber_message( sender, recipient, thread, body ) {

	if( sender == null || recipient == null || recipient.length < 1 ) { return; }

	this.doc = new DOMParser().parseFromString("<message></message>", "text/xml");
	this.root = this.doc.documentElement;
	this.root.setAttribute( "from", sender );
	this.root.setAttribute( "to", recipient );

	var body_node = this.doc.createElement("body");
	body_node.appendChild( this.doc.createTextNode( body ) );

	var thread_node = this.doc.createElement("thread");
	thread_node.appendChild( this.doc.createTextNode( thread ) );

	this.root.appendChild( body_node );
	this.root.appendChild( thread_node );

}

/** Builds a new message from raw xml.
  * If the message is a Jabber error message, then msg.is_error_msg
  * is set to true;
  */
jabber_message.prototype.from_xml = function( xml ) {
	var msg = new jabber_message();
	msg.doc = new DOMParser().parseFromString( xml, "text/xml" );
	msg.root = msg.doc.documentElement;

	if( msg.root.getAttribute( "type" ) == "error" ) {
		msg.is_error_msg = true;
	} else {
		this.is_error_msg = false;
	}

	return msg;
}

/** Returns the 'from' field of the message */
jabber_message.prototype.get_sender = function() {
	return this.root.getAttribute( "from" );
}

/** Returns the jabber thread */
jabber_message.prototype.get_thread = function() {
	var nodes = this.root.getElementsByTagName( "thread" );
	var thread_node = nodes.item(0);
	return thread_node.firstChild.nodeValue;
}

/** Returns the message body */
jabber_message.prototype.get_body = function() {
	var nodes = this.root.getElementsByTagName( "body" );
	var body_node = nodes.item(0);
	new Logger().transport( "Get Body returning:\n" + body_node.textContent, Logger.DEBUG );
	return body_node.textContent;
}
	
/** Returns the message as a whole as an XML string */
jabber_message.prototype.to_string = function() {
   return new XMLSerializer().serializeToString(this.root);
}




// ------------------------------------------------------------------
// TRANSPORT_SOCKET

/** Initializes a new jabber_socket object */
function jabber_socket() {

	this.is_connected	= false;
	this.outstream		= "";
	this.instream		= "";
	this.buffer			= "";
	this.socket			= "";

}

/** Connects to the jabber server */
jabber_socket.prototype.connect = 
	function( username, password, resource,  host, port, timeout ) {

	var starttime = new Date().getTime();

	// there has to be at least some kind of timeout
	if( ! timeout || timeout < 100 ) { timeout = 1000; }

	try {

		this.xpcom_init( host, port );
		this.tcp_send( "<stream:stream to='"+host
				+"' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>" );

		if( !this.tcp_recv( timeout ) ) {  throw 1; }

	} catch( E ) {
		throw new oils_ex_transport( "Could not open a socket to the transport server\n" 
				+ "Server: " + host + " Port: " + port  );
	}

	// Send the auth packet
	this.tcp_send( "<iq id='123456789' type='set'><query xmlns='jabber:iq:auth'><username>" 
			+ username + "</username><password>" + password + 
			"</password><resource>" + resource + "</resource></query></iq>" );

	var cur = new Date().getTime();
	var remaining = timeout - ( cur - starttime );
	this.tcp_recv( remaining );

	if( ! this.connected() ) {
		throw new oils_ex_transport( "Connection to transport server timed out" );
	}

	return true;


}


/** Sets up all of the xpcom components */
jabber_socket.prototype.xpcom_init = function( host, port ) {

	var transportService =
		Components.classes["@mozilla.org/network/socket-transport-service;1"]
		.getService(Components.interfaces.nsISocketTransportService);

	this.transport = transportService.createTransport( null, 0, host, port, null);

	// ------------------------------------------------------------------
	// Build the stream objects
	// ------------------------------------------------------------------
	this.outstream = this.transport.openOutputStream(0,0,0);
	
	var stream = this.transport.openInputStream(0,0,0);

	this.instream = Components.classes["@mozilla.org/scriptableinputstream;1"]
			.createInstance(Components.interfaces.nsIScriptableInputStream);

	this.instream.init(stream);

}

/** Send data to the TCP pipe */
jabber_socket.prototype.tcp_send = function( data ) {
	new Logger().transport( "Sending Data: \n" + data, Logger.INFO );
	this.outstream.write(data,data.length);
}


/** Accepts data coming directly from the socket.  If we're not
  * connected, we pass it off to procecc_connect().  Otherwise,
  * this method adds the data to the local buffer.
  */
jabber_socket.prototype.process_data = function( data ) {

	new Logger().transport( "Received TCP data: " + data, Logger.DEBUG );

	if( ! this.connected() ) {
		this.process_connect( data );
		return;
	} 

	this.buffer += data;

}

/** Processes connect data to verify we are logged in correctly */
jabber_socket.prototype.process_connect = function( data ) {

	var reg = /type=["\']result["\']/;
	var err = /error/;

	if( reg.exec( data ) ) {
		this.is_connected = true;
	} else {
		if( err.exec( data ) ) {
			//throw new oils_ex_transport( "Server returned: \n" + data );
			throw new oils_ex_jabber_auth( "Server returned: \n" + data );
			// Throw exception, return something...
		}
	}
}

/** Waits up to at most 'timeout' milliseconds for data to arrive 
  * in the TCP buffer.  If there is at least one byte of data 
  * in the buffer, then all of the data that is in the buffer is sent 
  * to the process_data method for processing and the method returns.  
  */
jabber_socket.prototype.tcp_recv = function( timeout ) {

	var count = this.instream.available();
	var did_receive = false;

	// ------------------------------------------------------------------
	// If there is any data in the tcp buffer, process it and return
	// ------------------------------------------------------------------
	if( count > 0 ) { 

		did_receive = true;
		while( count > 0 ) { 
			new Logger().transport(
				"before process data", Logger.DEBUG );

			this.process_data( this.instream.read( count ) );

			new Logger().transport(
				"after process data", Logger.DEBUG );

			count = this.instream.available();

			new Logger().transport(
				"received " + count + " bytes" , Logger.DEBUG );
		}

	} else { 

		// ------------------------------------------------------------------
		// Do the timeout dance
		// ------------------------------------------------------------------

		// ------------------------------------------------------------------
		// If there is no data in the buffer, wait up to timeout seconds
		// for some data to arrive.  Once it arrives, suck it all out
		// and send it on for processing
		// ------------------------------------------------------------------

		var now, then;
		now = new Date().getTime();
		then = now;

		// ------------------------------------------------------------------
		// Loop and poll for data every 50 ms.
		// ------------------------------------------------------------------
		while( ((now-then) <= timeout) && count <= 0 ) { 
			sleep(50);
			count = this.instream.available();
			now = new Date().getTime();
		}

		// ------------------------------------------------------------------
		// if we finally get some data, process it.
		// ------------------------------------------------------------------
		if( count > 0 ) {

			did_receive = true;
			while( count > 0 ) { // pull in all of the data there is
				this.process_data( this.instream.read( count ) );
				count = this.instream.available();
			}
		}
	}

	return did_receive;

}

/** If a message is already sitting in the queue, it is returned.  
  * If not, this method waits till at most 'timeout' milliseconds 
  * for a full jabber message to arrive and then returns that.
  * If none ever arrives, returns null.
  */
jabber_socket.prototype.recv = function( timeout ) {

	var now, then;
	now = new Date().getTime();
	then = now;

	var first_pass = true;
	while( ((now-then) <= timeout) ) {
		
		if( this.buffer.length == 0  || !first_pass ) {
			if( ! this.tcp_recv( timeout ) ) {
				return null;
			}
		}
		first_pass = false;

		//new Logger().transport( "\n\nTCP Buffer Before: \n" + this.buffer, Logger.DEBUG );

		var buf = this.buffer;
		this.buffer = "";

		new Logger().transport( "CURRENT BUFFER\n" + buf,
			Logger.DEBUG );

		buf = buf.replace( /\n/g, '' ); // remove pesky newlines

		var reg = /<message.*?>.*?<\/message>/;
		var iqr = /<iq.*?>.*?<\/iq>/;
		var out = reg.exec(buf);

		if( out ) { 

			var msg_xml = out[0];
			this.buffer = buf.substring( msg_xml.length, buf.length );
			new Logger().transport( "Building Jabber message\n\n" + msg_xml, Logger.DEBUG );
			var jab_msg = new jabber_message().from_xml( msg_xml );
			if( jab_msg.is_error_msg ) {
				new Logger().transport( "Received Jabber error message \n\n" + msg_xml, Logger.ERROR );
			} 

			return jab_msg;


		} else { 

			out = iqr.exec(buf);

			if( out ) {
				var msg_xml = out[0];
				this.buffer = buf.substring( msg_xml.length, buf.length );
				process_iq_data( msg_xml );
				return;

			} else {
				this.buffer = buf;
			}

		} 
		now = new Date().getTime();
	}

	return null;
}

jabber_socket.prototype.process_iq_data = function( data ) {
	new Logger().transport( "IQ Packet received... Not Implemented\n" + data, Logger.ERROR );
}

/** Disconnects from the jabber server and closes down shop */
jabber_socket.prototype.disconnect = function() {
	this.tcp_send( "</stream:stream>" );
	this.instream.close();
	this.outstream.close();
}

/** True if connected */
jabber_socket.prototype.connected = function() {
	return this.is_connected;
}






// -----------------------------------------------------------------------------
// Message stack code.
// -----------------------------------------------------------------------------



// -----------------------------------------------------------------------------
// These just have to be defined for the 'static' methods to work
// -----------------------------------------------------------------------------
function Transport() {}
function Message() {}
function Application() {}

/** Transport handler.  
  * Takes a transport_message as parameter
  * Parses the incoming message data and builds one or more oilsMessage objects
  * from the XML.  Each message is passed in turn to the Message.handler
  * method.
  */
Transport.handler = function( msg ) {

	if( msg.is_error_msg ) {
		throw new oils_ex_session( "Receved error message from jabber server for recipient: " + msg.get_sender() );
		return;
	}

	var remote_id	= msg.get_sender();
	var session_id = msg.get_thread();
	var body			= msg.get_body();

	var session		= AppSession.find_session( session_id );

	if( ! session ) {
		new Logger().debug( "No AppSession found with id: " + session_id );
		return;
	}

	session.set_remote_id( remote_id );

	var nodelist; // oilsMessage nodes


	// -----------------------------------------------------------------------------
	// Parse the incoming XML
	// -----------------------------------------------------------------------------
	try {

		var doc = new DOMParser().parseFromString( body, "text/xml" );
		nodelist = doc.documentElement.getElementsByTagName( "oils:domainObject" );

		if( ! nodelist || nodelist.length < 1 ) {
			nodelist = doc.documentElement.getElementsByTagName( "domainObject" );
			if( ! nodelist || nodelist.length < 1 ) { throw 1; }
		}

	} catch( E ) {

		var str = "Error parsing incoming message document";

		if( E ) { throw new oils_ex_dom( str + "\n" + E.message + "\n" + body ); 
		} else { throw new oils_ex_dom( str + "\n" + body ); }

	}
	
	// -----------------------------------------------------------------------------
	// Pass the messages up the chain.
	// -----------------------------------------------------------------------------
	try {

		var i = 0;
		var node = nodelist.item(i); // a single oilsMessage

		while( node != null ) {

			if( node.getAttribute("name") != "oilsMessage" ) {
				node = nodelist.item(++i);
				continue;
			}
				
			var oils_msg = new oilsMessage().replaceNode( node );  


			// -----------------------------------------------------------------------------
			// this is really inefficient compared to the above line of code,
			// however, this resolves some namespace oddities in DOMParser - 
			// namely, DOMParser puts dummy namesapaces in "a0" when, I'm assuming, it 
			// can't find the definition for the namesapace included.
			// -----------------------------------------------------------------------------
			//	var oils_msg = oilsMessage.newFromXML( new XMLSerializer().serializeToString( node ) );

			new Logger().transport( "Transport passing up:\n" + oils_msg.toString(true), Logger.INFO );

			// Pass the message off to the message layer
			Message.handler( session, oils_msg );
			node = nodelist.item(++i);
		}

	} catch( E ) {

		var str = "Processing Error";

		if( E ) { throw new oils_ex_session( str + "\n" + E.message + "\n" + body ); } 
		else { throw new oils_ex_session( str + "\n" + body ); }
	}
}

/** Checks to see what type of message has arrived.  If it is a 'STATUS' message,
  * the appropriate transport layer actions are taken.  Otherwise (RESULT), the
  * message is passed to the Application.handler method.
  */
Message.handler = function( session, msg ) {

	var msg_type					= msg.getType();
	var domain_object_payload	= msg.getPayload();
	var tt							= msg.getThreadTrace();

	var code = domain_object_payload.getStatusCode();

	new Logger().debug( "Message.handler received " + msg_type + " from " +
			session.get_remote_id() + " with thread_trace " + tt + " and status " + code, Logger.INFO );
	new Logger().debug( "Message.handler received:\n" + domain_object_payload.toString(), Logger.DEBUG );

	if( msg_type == oilsMessage.STATUS ) {

		switch( code ) {

			case  oilsResponse.STATUS_OK + "": {
				session.set_state( AppSession.CONNECTED );
				new Logger().debug( " * Connected Successfully: " + tt, Logger.INFO );
				return;
			}

			case oilsResponse.STATUS_TIMEOUT + "": {
				return Message.reset_session( session, tt, "Disconnected because of timeout" );
			}

			case oilsResponse.STATUS_REDIRECTED + "": {
				return Message.reset_session( session, tt, "Disconnected because of redirect" );
			}

			case oilsResponse.STATUS_EXPFAILED + "": {
				return Message.reset_session( session, tt, "Disconnected because of mangled session" );
			}

			case oilsResponse.STATUS_NOTALLOWED + "": {
				new Logger().debug( "Method Not Allowed", Logger.ERROR );
				session.destroy();
				break; // we want the exception to be thrown below
			}

			case oilsResponse.STATUS_CONTINUE +"": {
				return;
			}

			case oilsResponse.STATUS_COMPLETE + "": {
				var req = session.get_request(tt);
				if( req ) { 
					req.set_complete(); 
					new Logger().debug( " * Request completed: " + tt, Logger.INFO );
				}
				return;
			}

			default: { break; } 
		}

	}

	// throw any exceptions received from the server
	if( domain_object_payload instanceof oilsException ) {
		throw new oils_ex_session( domain_object_payload.getStatus() );
	}

	new Logger().debug( "Message Layer passing up:\n" + domain_object_payload.toString(), Logger.DEBUG );

	Application.handler( session, domain_object_payload, tt );

}

/** Utility method for cleaning up a session.  Sets state to disconnected.
  * resets the remoted_id, pushes the current app_request onto the resend
  * queue. Logs a message.
  */
Message.reset_session = function( session, thread_trace, message ) {
	session.set_state( AppSession.DISCONNECTED );
	session.reset_remote();
	var req = session.get_request( thread_trace );
	if( req && !req.complete() ) { session.push_resend( req ); }
	new Logger().debug( " * " + message + " : " + thread_trace, Logger.INFO );
}


/** Pushes all incoming messages onto the session message queue. **/
Application.handler = function( session, domain_object_payload, thread_trace ) {

	new Logger().debug( "Application Pushing onto queue: " 
			+ thread_trace + "\n" + domain_object_payload.toString(), Logger.DEBUG );

	session.push_queue( domain_object_payload, thread_trace );
}


	

	

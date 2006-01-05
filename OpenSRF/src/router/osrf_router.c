#include "osrf_router.h"

#define ROUTER_SOCKFD connection->session->sock_id
#define ROUTER_REGISTER "register"
#define ROUTER_UNREGISTER "unregister"


#define ROUTER_REQUEST_CLASS_LIST "opensrf.router.info.class.list"

osrfRouter* osrfNewRouter( 
		char* domain, char* name, 
		char* resource, char* password, int port, 
		osrfStringArray* trustedClients, osrfStringArray* trustedServers ) {

	if(!( domain && name && resource && password && port && trustedClients && trustedServers )) return NULL;

	osrfRouter* router	= safe_malloc(sizeof(osrfRouter));
	router->domain			= strdup(domain);
	router->name			= strdup(name);
	router->password		= strdup(password);
	router->resource		= strdup(resource);
	router->port			= port;

	router->trustedClients = trustedClients;
	router->trustedServers = trustedServers;

	
	router->classes = osrfNewHash(); 
	router->classes->freeItem = &osrfRouterClassFree;

	router->connection = client_init( domain, port, NULL, 0 );

	return router;
}



int osrfRouterConnect( osrfRouter* router ) {
	if(!router) return -1;
	int ret = client_connect( router->connection, router->name, 
			router->password, router->resource, 10, AUTH_DIGEST );
	if( ret == 0 ) return -1;
	return 0;
}


void osrfRouterRun( osrfRouter* router ) {
	if(!(router && router->classes)) return;

	int routerfd = router->ROUTER_SOCKFD;
	int selectret = 0;

	while(1) {

		fd_set set;
		int maxfd = __osrfRouterFillFDSet( router, &set );
		int numhandled = 0;

		if( (selectret = select(maxfd + 1, &set, NULL, NULL, NULL)) < 0 ) {
			osrfLogWarning("Top level select call failed with errno %d", errno);
			continue;
		}

		/* see if there is a top level router message */

		if( FD_ISSET(routerfd, &set) ) {
			osrfLogDebug("Top router socket is active: %d", routerfd );
			numhandled++;
			osrfRouterHandleIncoming( router );
		}


		/* now check each of the connected classes and see if they have data to route */
		while( numhandled < selectret ) {

			osrfRouterClass* class;
			osrfHashIterator* itr = osrfNewHashIterator(router->classes);

			while( (class = osrfHashIteratorNext(itr)) ) {

				char* classname = itr->current;

				if( classname && (class = osrfRouterFindClass( router, classname )) ) {

					osrfLogDebug("Checking %s for activity...", classname );

					int sockfd = class->ROUTER_SOCKFD;
					if(FD_ISSET( sockfd, &set )) {
						osrfLogDebug("Socket is active: %d", sockfd );
						numhandled++;
						osrfRouterClassHandleIncoming( router, classname, class );
					}
				}
			}

			osrfHashIteratorFree(itr);
		}
	}
}


void osrfRouterHandleIncoming( osrfRouter* router ) {
	if(!router) return;

	transport_message* msg = NULL;

	if( (msg = client_recv( router->connection, 0 )) ) { 

		if( msg->sender ) {

			/* if the sender is not a trusted server, drop the message */
			int len = strlen(msg->sender) + 1;
			char domain[len];
			bzero(domain, len);
			jid_get_domain( msg->sender, domain, len - 1 );

			if(osrfStringArrayContains( router->trustedServers, domain)) 
				osrfRouterHandleMessage( router, msg );
			 else 
				osrfLogWarning("Received message from un-trusted server domain %s", msg->sender);
		}

		message_free(msg);
	}
}

int osrfRouterClassHandleIncoming( osrfRouter* router, char* classname, osrfRouterClass* class ) {
	if(!(router && class)) return -1;

	transport_message* msg;
	osrfLogDebug("osrfRouterClassHandleIncoming()");

	if( (msg = client_recv( class->connection, 0 )) ) {

		if( msg->sender ) {

			/* if the client is not from a trusted domain, drop the message */
			int len = strlen(msg->sender) + 1;
			char domain[len];
			bzero(domain, len);
			jid_get_domain( msg->sender, domain, len - 1 );

			if(osrfStringArrayContains( router->trustedClients, domain)) {

				transport_message* bouncedMessage = NULL;
				if( msg->is_error )  {

					/* handle bounced message */
					if( !(bouncedMessage = osrfRouterClassHandleBounce( router, classname, class, msg )) ) 
						return -1; /* we have no one to send the requested message to */

					message_free( msg );
					msg = bouncedMessage;
				}
				osrfRouterClassHandleMessage( router, class, msg );

			} else {
				osrfLogWarning("Received client message from untrusted client domain %s", domain );
			}
		}

		message_free( msg );
	}

	return 0;
}




int osrfRouterHandleMessage( osrfRouter* router, transport_message* msg ) {
	if(!(router && msg)) return -1;

	if( !msg->router_command || !strcmp(msg->router_command,"")) 
		return osrfRouterHandleAppRequest( router, msg ); /* assume it's an app session level request */

	if(!msg->router_class) return -1;

	osrfRouterClass* class = NULL;
	if(!strcmp(msg->router_command, ROUTER_REGISTER)) {
		class = osrfRouterFindClass( router, msg->router_class );

		osrfLogInfo("Registering class %s", msg->router_class );

		if(!class) class = osrfRouterAddClass( router, msg->router_class );

		if(class) { 

			if( osrfRouterClassFindNode( class, msg->sender ) )
				return 0;
			else 
				osrfRouterClassAddNode( class, msg->sender );

		} 

	} else if( !strcmp( msg->router_command, ROUTER_UNREGISTER ) ) {

		if( msg->router_class && strcmp( msg->router_class, "") ) {
			osrfLogInfo("Unregistering router class %s", msg->router_class );
			osrfRouterClassRemoveNode( router, msg->router_class, msg->sender );
		}
	}

	return 0;
}



osrfRouterClass* osrfRouterAddClass( osrfRouter* router, char* classname ) {
	if(!(router && router->classes && classname)) return NULL;

	osrfRouterClass* class = safe_malloc(sizeof(osrfRouterClass));
	class->nodes = osrfNewHash();
	class->itr = osrfNewHashIterator(class->nodes);
	class->nodes->freeItem = &osrfRouterNodeFree;
	class->router	= router;

	class->connection = client_init( router->domain, router->port, NULL, 0 );

	if(!client_connect( class->connection, router->name, 
			router->password, classname, 10, AUTH_DIGEST ) ) {
		osrfRouterClassFree( classname, class );
		return NULL;
	}
	
	osrfHashSet( router->classes, class, classname );
	return class;
}


int osrfRouterClassAddNode( osrfRouterClass* rclass, char* remoteId ) {
	if(!(rclass && rclass->nodes && remoteId)) return -1;

	osrfLogInfo("Adding router node for remote id %s", remoteId );

	osrfRouterNode* node = safe_malloc(sizeof(osrfRouterNode));
	node->count = 0;
	node->lastMessage = NULL;
	node->remoteId = strdup(remoteId);

	osrfHashSet( rclass->nodes, node, remoteId );
	return 0;
}

/* copy off the lastMessage, remove the offending node, send error if it's tht last node 
	? return NULL if it's the last node ?
 */

transport_message* osrfRouterClassHandleBounce( 
		osrfRouter* router, char* classname, osrfRouterClass* rclass, transport_message* msg ) {

	osrfLogDebug("osrfRouterClassHandleBounce()");

	osrfLogInfo("Received network layer error message from %s", msg->sender );
	osrfRouterNode* node = osrfRouterClassFindNode( rclass, msg->sender );
	transport_message* lastSent = NULL;

	if( node && osrfHashGetCount(rclass->nodes) == 1 ) { /* the last node is dead */

		if( node->lastMessage ) {
			osrfLogWarning("We lost the last node in the class, responding with error and removing...");
	
			transport_message* error = message_init( 
				node->lastMessage->body, node->lastMessage->subject, 
				node->lastMessage->thread, node->lastMessage->router_from, node->lastMessage->recipient );
			set_msg_error( error, "cancel", 501 );
	
			/* send the error message back to the original sender */
			client_send_message( rclass->connection, error );
			message_free( error );
		}
	
		return NULL;
	
	} else { 

		if( node->lastMessage ) {
			osrfLogDebug("Cloning lastMessage so next node can send it");
			lastSent = message_init( node->lastMessage->body,
				node->lastMessage->subject, node->lastMessage->thread, "", node->lastMessage->router_from );
			message_set_router_info( lastSent, node->lastMessage->router_from, NULL, NULL, NULL, 0 );
		}
	}

	/* remove the dead node */
	osrfRouterClassRemoveNode( router, classname, msg->sender);
	return lastSent;
}


/**
  If we get a regular message, we send it to the next node in the list of nodes
  if we get an error, it's a bounce back from a previous attempt.  We take the
  body and thread from the last sent on the node that had the bounced message
  and propogate them on to the new message being sent
  */
int osrfRouterClassHandleMessage( 
		osrfRouter* router, osrfRouterClass* rclass, transport_message* msg ) {
	if(!(router && rclass && msg)) return -1;

	osrfLogDebug("osrfRouterClassHandleMessage()");

	osrfRouterNode* node = osrfHashIteratorNext( rclass->itr );
	if(!node) {
		osrfHashIteratorReset(rclass->itr);
		node = osrfHashIteratorNext( rclass->itr );
	}

	if(node) {

		transport_message* new_msg= message_init(	msg->body, 
				msg->subject, msg->thread, node->remoteId, msg->sender );
		message_set_router_info( new_msg, msg->sender, NULL, NULL, NULL, 0 );

		osrfLogInfo( "Routing message:\nfrom: [%s]\nto: [%s]", 
				new_msg->router_from, new_msg->recipient );

		message_free( node->lastMessage );
		node->lastMessage = new_msg;

		if ( client_send_message( rclass->connection, new_msg ) == 0 ) 
			node->count++;

		else {
			message_prepare_xml(new_msg);
			osrfLogWarning("Error sending message from %s to %s\n%s", 
					new_msg->sender, new_msg->recipient, new_msg->msg_xml );
		}

	} 

	return 0;
}


int osrfRouterRemoveClass( osrfRouter* router, char* classname ) {
	if(!(router && router->classes && classname)) return -1;
	osrfLogInfo("Removing router class %s", classname );
	osrfHashRemove( router->classes, classname );
	return 0;
}


int osrfRouterClassRemoveNode( 
		osrfRouter* router, char* classname, char* remoteId ) {

	if(!(router && router->classes && classname && remoteId)) return 0;

	osrfLogInfo("Removing router node %s", remoteId );

	osrfRouterClass* class = osrfRouterFindClass( router, classname );

	if( class ) {

		osrfHashRemove( class->nodes, remoteId );
		if( osrfHashGetCount(class->nodes) == 0 ) {
			osrfRouterRemoveClass( router, classname );
			return 1;
		}

		return 0;
	}

	return -1;
}


void osrfRouterClassFree( char* classname, void* c ) {
	if(!(classname && c)) return;
	osrfRouterClass* rclass = (osrfRouterClass*) c;
	client_disconnect( rclass->connection );	
	client_free( rclass->connection );	

	osrfHashIteratorReset( rclass->itr );
	osrfRouterNode* node;

	while( (node = osrfHashIteratorNext(rclass->itr)) ) 
		osrfRouterClassRemoveNode( rclass->router, classname, node->remoteId );

	free(rclass);
}


void osrfRouterNodeFree( char* remoteId, void* n ) {
	if(!n) return;
	osrfRouterNode* node = (osrfRouterNode*) n;
	free(node->remoteId);
	message_free(node->lastMessage);
	free(node);
}


void osrfRouterFree( osrfRouter* router ) {
	if(!router) return;

	free(router->domain);		
	free(router->name);
	free(router->resource);
	free(router->password);

	osrfStringArrayFree( router->trustedClients );
	osrfStringArrayFree( router->trustedServers );

	client_free( router->connection );
	free(router);
}



osrfRouterClass* osrfRouterFindClass( osrfRouter* router, char* classname ) {
	if(!( router && router->classes && classname )) return NULL;
	return (osrfRouterClass*) osrfHashGet( router->classes, classname );
}


osrfRouterNode* osrfRouterClassFindNode( osrfRouterClass* rclass, char* remoteId ) {
	if(!(rclass && remoteId))  return NULL;
	return (osrfRouterNode*) osrfHashGet( rclass->nodes, remoteId );
}


int __osrfRouterFillFDSet( osrfRouter* router, fd_set* set ) {
	if(!(router && router->classes && set)) return -1;

	FD_ZERO(set);
	int maxfd = router->ROUTER_SOCKFD;
	FD_SET(maxfd, set);

	int sockid;

	osrfRouterClass* class = NULL;
	osrfHashIterator* itr = osrfNewHashIterator(router->classes);

	while( (class = osrfHashIteratorNext(itr)) ) {
		char* classname = itr->current;

		if( classname && (class = osrfRouterFindClass( router, classname )) ) {
			sockid = class->ROUTER_SOCKFD;
	
			if( osrfUtilsCheckFileDescriptor( sockid ) ) {
				osrfRouterRemoveClass( router, classname );
	
			} else {
				if( sockid > maxfd ) maxfd = sockid;
				FD_SET(sockid, set);
			}
		}
	}

	osrfHashIteratorFree(itr);
	return maxfd;
}



int osrfRouterHandleAppRequest( osrfRouter* router, transport_message* msg ) {

	int T = 32;
	osrfMessage* arr[T];
	memset(arr, 0, T );

	int num_msgs = osrf_message_deserialize( msg->body, arr, T );
	osrfMessage* omsg = NULL;

	int i;
	for( i = 0; i != num_msgs; i++ ) {

		if( !(omsg = arr[i]) ) continue;

		switch( omsg->m_type ) {

			case CONNECT:
				osrfRouterRespondConnect( router, msg, omsg );
				break;

			case REQUEST:
				osrfRouterProcessAppRequest( router, msg, omsg );
				break;

			default: break;
		}

		osrfMessageFree( omsg );
	}

	return 0;
}

int osrfRouterRespondConnect( osrfRouter* router, transport_message* msg, osrfMessage* omsg ) {
	if(!(router && msg && omsg)) return -1;

	osrfMessage* success = osrf_message_init( STATUS, omsg->thread_trace, omsg->protocol );

	osrfLogDebug("router recevied a CONNECT message from %s", msg->sender );

	osrf_message_set_status_info( 
		success, "osrfConnectStatus", "Connection Successful", OSRF_STATUS_OK );

	char* data	= osrf_message_serialize(success);

	transport_message* return_m = message_init( 
		data, "", msg->thread, msg->sender, "" );

	client_send_message(router->connection, return_m);

	free(data);
	osrf_message_free(success);
	message_free(return_m);

	return 0;
}



int osrfRouterProcessAppRequest( osrfRouter* router, transport_message* msg, osrfMessage* omsg ) {

	if(!(router && msg && omsg && omsg->method_name)) return -1;

	osrfLogInfo("Router received app request: %s", omsg->method_name );

	jsonObject* jresponse = NULL;
	if(!strcmp( omsg->method_name, ROUTER_REQUEST_CLASS_LIST )) {

		int i;
		jresponse = jsonParseString("[]");

		osrfStringArray* keys = osrfHashKeys( router->classes );
		for( i = 0; i != keys->size; i++ )
			jsonObjectPush( jresponse, jsonNewObject(osrfStringArrayGetString( keys, i )) );
		osrfStringArrayFree(keys);


	} else {

		return osrfRouterHandleMethodNFound( router, msg, omsg );
	}


	osrfRouterHandleAppResponse( router, msg, omsg, jresponse );
	jsonObjectFree(jresponse); 

	return 0;

}



int osrfRouterHandleMethodNFound( 
		osrfRouter* router, transport_message* msg, osrfMessage* omsg ) {

	osrf_message* err = osrf_message_init( STATUS, omsg->thread_trace, 1);
		osrf_message_set_status_info( err, 
				"osrfMethodException", "Router method not found", OSRF_STATUS_NOTFOUND );

		char* data =  osrf_message_serialize(err);

		transport_message* tresponse = message_init(
				data, "", msg->thread, msg->sender, msg->recipient );

		client_send_message(router->connection, tresponse );

		free(data);
		osrf_message_free( err );
		message_free(tresponse);
		return 0;
}



int osrfRouterHandleAppResponse( osrfRouter* router, 
	transport_message* msg, osrfMessage* omsg, jsonObject* response ) {

	if( response ) { /* send the response message */

		osrfMessage* oresponse = osrf_message_init(
				RESULT, omsg->thread_trace, omsg->protocol );
	
		char* json = jsonObjectToJSON(response);
		osrf_message_set_result_content( oresponse, json);
	
		char* data =  osrf_message_serialize(oresponse);
		osrfLogDebug( "Responding to client app request with data: \n%s\n", data );

		transport_message* tresponse = message_init(
				data, "", msg->thread, msg->sender, msg->recipient );
	
		client_send_message(router->connection, tresponse );

		osrfMessageFree(oresponse); 
		message_free(tresponse);
		free(json);
		free(data);
	}


	/* now send the 'request complete' message */
	osrf_message* status = osrf_message_init( STATUS, omsg->thread_trace, 1);
	osrf_message_set_status_info( status, "osrfConnectStatus", "Request Complete", OSRF_STATUS_COMPLETE );

	char* statusdata = osrf_message_serialize(status);

	transport_message* sresponse = message_init(
			statusdata, "", msg->thread, msg->sender, msg->recipient );
	client_send_message(router->connection, sresponse );


	free(statusdata);
	osrfMessageFree(status);
	message_free(sresponse);

	return 0;
}





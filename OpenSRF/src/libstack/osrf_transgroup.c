#include "osrf_transgroup.h"
#include <sys/select.h>


osrfTransportGroupNode* osrfNewTransportGroupNode( 
		char* domain, int port, char* username, char* password, char* resource ) {

	if(!(domain && port && username && password && resource)) return NULL;

	osrfTransportGroupNode* node = safe_malloc(sizeof(osrfTransportGroupNode));
	node->domain	= strdup(domain);
	node->port		= port;
	node->username = strdup(username);
	node->password = strdup(password);
	node->domain	= strdup(domain);
	node->active	= 0;
	node->lastsent	= 0;
	node->connection = client_init( domain, port, NULL, 0 );

	return node;
}


osrfTransportGroup* osrfNewTransportGroup( char* router, osrfTransportGroupNode* nodes[], int count ) {
	if(!nodes || !router || count < 1) return NULL;

	osrfTransportGroup* grp = safe_malloc(sizeof(osrfTransportGroup));
	grp->currentNode			= 0;
	grp->router					= strdup(router);
	grp->list					= osrfNewList(1);

	int i;
	for( i = 0; i != count; i++ ) osrfListPush( grp->list, nodes[i] );
	return grp;
}


int osrfTransportGroupConnect( osrfTransportGroup* grp ) {
	if(!grp) return 0;
	int i;
	int active = 0;
	for( i = 0; i != grp->list->size; i++ ) {
		osrfTransportGroupNode* node = osrfListGetIndex( grp->list, i );
		if(client_connect( node->connection, node->username, 
					node->password, node->resource, 10, AUTH_DIGEST )) {
			node->active = 1;
			node->lastsent = time(NULL);
			active++;
		}
	}
	return active;
}


/*
osrfTransportGroup* osrfNewTransportGroup( char* resource ) {

	grp->username				= osrfConfigGetValue( NULL, "/username" );
	grp->password				= osrfConfigGetValue( NULL, "/passwd" );
	char* port					= osrfConfigGetValue( NULL, "/port" );
	if(port) grp->port		= atoi(port);
	grp->currentNode			= 0;

	if(!resource) resource = "client";
	char* host = getenv("HOSTNAME");
	if(!host) host = "localhost";
	char* res = va_list_to_string( "osrf_%s_%s_%d", resource, host, getpid() ); 

	int i;
	osrfStringArray* arr = osrfNewStringArray(8); 
	osrfConfigGetValueList(NULL, arr, "/domains/domain");

	for( i = 0; i != arr->size; i++ ) {
		char* domain = osrfStringArrayGetString( arr, i ); 
		if(domain) {
			node->domain = strdup(domain);
			node->connection = client_init( domain, grp->port, NULL, 0 );
			if(client_connect( node->connection, grp->username, grp->password, res, 10, AUTH_DIGEST )) {
				node->active = 1;
				node->lastsent = time(NULL);
			}
			osrfListPush( grp->list, node );
		}
	}

	free(res);
	osrfStringArrayFree(arr);
	return grp;
}
*/


int osrfTransportGroupSend( osrfTransportGroup* grp, transport_message* msg, char* newdomain ) {
	if(!(grp && msg)) return -1;

	char domain[256];
	bzero(domain, 256);
	jid_get_domain( msg->recipient, domain );

	char msgrecip[254];
	bzero(msgrecip, 254);
	jid_get_username(msg->recipient, msgrecip);


	osrfTransportGroupNode* node = __osrfTransportGroupFindNode( grp, domain );

	if( strcmp( msgrecip, grp->router ) ) { /* not a top level router message */

		if(node) {
			if( (client_send_message( node->connection, msg )) == 0 )
				return 0;
			else 
				return warning_handler("Error sending message to domain %s", domain );
		}
		return warning_handler("Transport group has no node for domain %s", domain );
	}


	/*
	if( type == OSRF_SERVER_NODE )
		return _osrfTGServerSend( grp, msgdom, msg );
	if( type == OSRF_CLIENT_NODE )
		return _osrfTGClientSend( grp, msgdom, msg );
		*/

	return -1;
}

int _osrfTGServerSend( osrfTransportGroup* grp, char* domain, transport_message* msg ) {

	debug_handler("Transport group sending server message to domain %s", domain );

	osrfTransportGroupNode* node = __osrfTransportGroupFindNode( grp, domain );
	if(node) {
		if( (client_send_message( node->connection, msg )) == 0 )
			return 0;
		else 
			return warning_handler("Error sending server response to domain %s", domain );
	}
	return warning_handler("Transport group has no node for domain %s for server response", domain );
}


int _osrfTGClientSend( osrfTransportGroup* grp, char* domain, transport_message* msg ) {

	debug_handler("Transport group sending client message to domain %s", domain );

	/* first see if we have a node for the requested domain */
	osrfTransportGroupNode* node = __osrfTransportGroupFindNode( grp, domain );
	if(node && node->active) {
		if( (client_send_message( node->connection, msg )) == 0 )
			return 0;
		else
			node->active = 0;
	}

	/* if not (or it fails), try sending to the current domain */
	node = osrfListGetIndex(grp->list, grp->currentNode);
	if(node && node->active) {
		if( (client_send_message( node->connection, msg )) == 0 )
			return 0;
	}

	/* start at the beginning and try them all ... */
	grp->currentNode = 0;
	while( grp->currentNode < grp->list->size ) {
		if( (node = osrfListGetIndex(grp->list, grp->currentNode++)) && node->active ) {
			if( (client_send_message( node->connection, msg )) == 0 ) 
				return 1;
			else node->active = 0;
		}
	}
	return -1;
}

static int __osrfTGWait( fd_set* fdset, int maxfd, int timeout ) {
	if(!(fdset && maxfd)) return 0;

	struct timeval tv;
	tv.tv_sec = timeout;
	tv.tv_usec = 0;
	int retval = 0;

	if( timeout < 0 ) {
		if( (retval = select( maxfd + 1, fdset, NULL, NULL, NULL)) == -1 ) 
			return 0;

	} else {
		if( (retval = select( maxfd + 1, fdset, NULL, NULL, &tv)) == -1 ) 
			return 0;
	}

	return retval;
}


transport_message* osrfTransportGroupRecvAll( osrfTransportGroup* grp, int timeout ) {
	if(!(grp && grp->list)) return NULL;

	int i;
	int maxfd = 0;
	osrfTransportGroupNode* node = NULL;
	fd_set fdset;
	FD_ZERO( &fdset );

	for( i = 0; i != grp->list->size; i++ ) {
		if( (node = osrfListGetIndex(grp->list, grp->currentNode++)) && node->active ) {
			int fd = node->connection->session->sock_id;
			if( fd < maxfd ) maxfd = fd;
			FD_SET( fd, &fdset );
		}
	}

	if( __osrfTGWait( &fdset, maxfd, timeout ) ) {
		for( i = 0; i != grp->list->size; i++ ) {
			if( (node = osrfListGetIndex(grp->list, grp->currentNode++)) && node->active ) {
				int fd = node->connection->session->sock_id;
				if( FD_ISSET( fd, &fdset ) ) {
					return client_recv( node->connection, 0 );
				}
			}
		}
	}

	return NULL;
}

transport_message* osrfTransportGroupRecv( osrfTransportGroup* grp, char* domain, int timeout ) {
	if(!(grp && domain)) return NULL;

	osrfTransportGroupNode* node = __osrfTransportGroupFindNode( grp, domain );
	if(!node && node->connection && node->connection->session) return NULL;
	int fd = node->connection->session->sock_id;

	fd_set fdset;
	FD_ZERO( &fdset );
	FD_SET( fd, &fdset );

	int active = __osrfTGWait( &fdset, fd, timeout );
	if(active) return client_recv( node->connection, 0 );
	
	return NULL;
}

void osrfTransportGroupSetInactive( osrfTransportGroup* grp, char* domain ) {
	if(!(grp && domain)) return;
	osrfTransportGroupNode* node = __osrfTransportGroupFindNode( grp, domain );
	if(node) node->active = 0;
}

osrfTransportGroupNode* __osrfTransportGroupFindNode( osrfTransportGroup* grp, char* domain ) {
	if(!(grp && grp->list && domain)) return NULL;
	int i = 0; 
	osrfTransportGroupNode* node = NULL;

	while( (node = (osrfTransportGroupNode*) osrfListGetIndex( grp->list, i++ )) ) 
		if(!strcmp(node->domain, domain)) return node;
	return NULL;
}





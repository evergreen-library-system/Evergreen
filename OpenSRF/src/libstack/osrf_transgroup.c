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
	node->resource	= strdup(resource);
	node->active	= 0;
	node->lastsent	= 0;
	node->connection = client_init( domain, port, NULL, 0 );

	return node;
}


osrfTransportGroup* osrfNewTransportGroup( osrfTransportGroupNode* nodes[], int count ) {
	if(!nodes || count < 1) return NULL;

	osrfTransportGroup* grp = safe_malloc(sizeof(osrfTransportGroup));
	grp->nodes					= osrfNewHash();
	grp->itr						= osrfNewHashIterator(grp->nodes);

	int i;
	for( i = 0; i != count; i++ ) {
		if(!(nodes[i] && nodes[i]->domain) ) return NULL;
		osrfHashSet( grp->nodes, nodes[i], nodes[i]->domain );
		debug_handler("Adding domain %s to TransportGroup", nodes[i]->domain);
	}

	return grp;
}


/* connect all of the nodes to their servers */
int osrfTransportGroupConnectAll( osrfTransportGroup* grp ) {
	if(!grp) return -1;
	int active = 0;

	osrfTransportGroupNode* node;
	osrfHashIteratorReset(grp->itr);

	while( (node = osrfHashIteratorNext(grp->itr)) ) {
		info_handler("TransportGroup attempting to connect to domain %s", 
							 node->connection->session->server);

		if(client_connect( node->connection, node->username, 
					node->password, node->resource, 10, AUTH_DIGEST )) {
			node->active = 1;
			active++;
			info_handler("TransportGroup successfully connected to domain %s", 
							 node->connection->session->server);
		} else {
			warning_handler("TransportGroup unable to connect to domain %s", 
							 node->connection->session->server);
		}
	}

	osrfHashIteratorReset(grp->itr);
	return active;
}

void osrfTransportGroupDisconnectAll( osrfTransportGroup* grp ) {
	if(!grp) return;

	osrfTransportGroupNode* node;
	osrfHashIteratorReset(grp->itr);

	while( (node = osrfHashIteratorNext(grp->itr)) ) {
		info_handler("TransportGroup disconnecting from domain %s", 
							 node->connection->session->server);
		client_disconnect(node->connection);
		node->active = 0;
	}

	osrfHashIteratorReset(grp->itr);
}


int osrfTransportGroupSendMatch( osrfTransportGroup* grp, transport_message* msg ) {
	if(!(grp && msg)) return -1;

	char domain[256];
	bzero(domain, 256);
	jid_get_domain( msg->recipient, domain, 255 );

	osrfTransportGroupNode* node = osrfHashGet(grp->nodes, domain);
	if(node) {
		if( (client_send_message( node->connection, msg )) == 0 )
			return 0;
	}

	return warning_handler("Error sending message to domain %s", domain );
}

int osrfTransportGroupSend( osrfTransportGroup* grp, transport_message* msg ) {

	if(!(grp && msg)) return -1;
	int bufsize = 256;

	char domain[bufsize];
	bzero(domain, bufsize);
	jid_get_domain( msg->recipient, domain, bufsize - 1 );

	char msgrecip[bufsize];
	bzero(msgrecip, bufsize);
	jid_get_username(msg->recipient, msgrecip, bufsize - 1);

	char msgres[bufsize];
	bzero(msgres, bufsize);
	jid_get_resource(msg->recipient, msgres, bufsize - 1);

	char* firstdomain = NULL;
	char newrcp[1024];

	int updateRecip = 1;
	/* if we don't host this domain, don't update the recipient but send it as is */
	if(!osrfHashGet(grp->nodes, domain)) updateRecip = 0;

	osrfTransportGroupNode* node;

	do {

		node = osrfHashIteratorNext(grp->itr);
		if(!node) osrfHashIteratorReset(grp->itr);

		node = osrfHashIteratorNext(grp->itr);
		if(!node) return -1;

		if(firstdomain == NULL) {
			firstdomain = node->domain;

		} else {
			if(!strcmp(firstdomain, node->domain)) { /* we've made a full loop */
				return warning_handler("We've tried to send to all domains.. giving up");
			}
		}

		/* update the recipient domain if necessary */

		if(updateRecip) {
			bzero(newrcp, 1024);
			sprintf(newrcp, "%s@%s/%s", msgrecip, node->domain, msgres);
			free(msg->recipient);
			msg->recipient = strdup(newrcp);
		}

		if( (client_send_message( node->connection, msg )) == 0 ) 
			return 0;

	} while(1);

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
	if(!grp) return NULL;

	int maxfd = 0;
	fd_set fdset;
	FD_ZERO( &fdset );

	osrfTransportGroupNode* node;
	osrfHashIterator* itr = osrfNewHashIterator(grp->nodes);

	while( (node = osrfHashIteratorNext(itr)) ) {
		if(node->active) {
			int fd = node->connection->session->sock_id;
			if( fd < maxfd ) maxfd = fd;
			FD_SET( fd, &fdset );
		}
	}
	osrfHashIteratorReset(itr);

	if( __osrfTGWait( &fdset, maxfd, timeout ) ) {
		while( (node = osrfHashIteratorNext(itr)) ) {
			if(node->active) {
				int fd = node->connection->session->sock_id;
				if( FD_ISSET( fd, &fdset ) ) {
					return client_recv( node->connection, 0 );
				}
			}
		}
	}

	osrfHashIteratorFree(itr);
	return NULL;
}

transport_message* osrfTransportGroupRecv( osrfTransportGroup* grp, char* domain, int timeout ) {
	if(!(grp && domain)) return NULL;

	osrfTransportGroupNode* node = osrfHashGet(grp->nodes, domain);
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
	osrfTransportGroupNode* node = osrfHashGet(grp->nodes, domain );
	if(node) node->active = 0;
}



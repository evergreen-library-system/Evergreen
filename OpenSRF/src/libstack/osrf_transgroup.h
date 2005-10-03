#include "opensrf/transport_client.h"
#include "opensrf/transport_message.h"
#include "osrf_list.h"
#include "osrfConfig.h"
#include "opensrf/utils.h"
#include <time.h>

/**
  Maintains a set of transport clients for redundancy
  */

//enum osrfTGType { OSRF_SERVER_NODE, OSRF_CLIENT_NODE };

struct __osrfTransportGroupStruct {
	osrfList* list;	/* our lisit of nodes */
	char* router;							/* the login username of the router on this network */
	int currentNode;	/* which node are we currently on.  Used for client failover and
								only gets updated on client messages where a server failed 
								and we need to move to the next server in the list */
};
typedef struct __osrfTransportGroupStruct osrfTransportGroup;


struct __osrfTransportGroupNode {
	transport_client* connection;		/* our connection to the network */
	char* domain;							/* the domain we're connected to */
	char* username;						/* username used to connect to the group of servers */
	char* password;						/* password used to connect to the group of servers */
	char* resource;						/* the login resource */
	int port;								/* port used to connect to the group of servers */

	int active;								/* true if we're able to send data on this connection */
	time_t lastsent;						/* the last time we sent a message */
};
typedef struct __osrfTransportGroupNode osrfTransportGroupNode;


/**
  Creates a new group node
  @param domain The domain we're connecting to
  @param port The port to connect on
  @param username The login name
  @param password The login password
  @param resource The login resource
  @return A new transport group node
  */
osrfTransportGroupNode* osrfNewTransportGroupNode( 
		char* domain, int port, char* username, char* password, char* resource );


/**
  Allocates and initializes a new transport group.
  The first node in the array is the default node for client connections.
  @param router The router name shared accross the networks
  @param nodes The nodes in the group.
  */
osrfTransportGroup* osrfNewTransportGroup( char* router, osrfTransportGroupNode* nodes[], int count );

/**
  Attempts to connect all of the nodes in this group.
  @param grp The transport group
  @return The number of nodes successfully connected
  */
int osrfTransportGroupConnect( osrfTransportGroup* grp );


/**
  Sends a transport message
  If the message is destined for a domain that this group does not have a connection
  for, then the message is sent out through the currently selected domain.
  @param grp The transport group
  @param type Whether this is a client request or a server response
  @param msg The message to send 
  @param newdomain A pre-allocated buffer in which to write the name of the 
  new domain if a the expected domain could not be sent to.
  @return 0 on normal successful send.  Returns 1 if the message was sent
  to a new domain (note: this can only happen when type == OSRF_CLIENT_NODE)
  Returns -1 if the message cannot be sent.  
  */
int osrfTransportGroupSend( osrfTransportGroup* grp, transport_message* msg, char* newdomain );

int _osrfTGServerSend( osrfTransportGroup* grp, char* domain, transport_message* msg );
int _osrfTGClientSend( osrfTransportGroup* grp, char* domain, transport_message* msg );

/**
  Waits on all connections for inbound data.
  @param grp The transport group
  @param timeout How long to wait for data.  0 means check for data
  but don't wait, a negative number means to wait indefinitely
  @return The received message or NULL if the timeout occurred before a 
  message was received 
 */
transport_message* osrfTransportGroupRecvAll( osrfTransportGroup* grp, int timeout );

/**
  Waits for data from a single domain
  @param grp The transport group
  @param domain The domain to wait for data on
  @param timeout see osrfTransportGroupRecvAll
  */
transport_message* osrfTransportGroupRecv( osrfTransportGroup* grp, char* domain, int timeout );

/**
  Tells the group that the connect to the last message sent to the provided
  domain did not make it through;
  @param grp The transport group
  @param comain The failed domain
  */
void osrfTransportGroupSetInactive( osrfTransportGroup* grp, char* domain );


/**
  Finds a node in our list of nodes 
  */
osrfTransportGroupNode* __osrfTransportGroupFindNode( osrfTransportGroup* grp, char* domain );



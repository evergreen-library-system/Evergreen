#include "opensrf/transport_client.h"
#include "opensrf/transport_message.h"
#include "osrf_list.h"
#include "osrf_hash.h"
#include "osrfConfig.h"
#include "opensrf/utils.h"
#include <time.h>

/**
  Maintains a set of transport clients 
  */

struct __osrfTransportGroupStruct {
	osrfHash* nodes;						/* our hash of nodes keyed by domain */
	osrfHashIterator* itr;				/* points to the next node in the list */
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
  Sends a transport message by going to the next domain in the set.
  if we have a connection for the recipient domain, then we consider it to be
  a 'local' message.  Local messages have their recipient domains re-written to
  match the domain of the next server in the set and they are sent directly to 
  that server.  If we do not have a connection for the recipient domain, it is 
  considered a 'remote' message and the message is sent directly (unchanged)
  to the next connection in the set.

  @param grp The transport group
  @param msg The message to send 
  @return 0 on normal successful send.  
  Returns -1 if the message cannot be sent.  
  */
int osrfTransportGroupSend( osrfTransportGroup* grp, transport_message* msg );

/**
  Sends the message to the exact recipient.  No failover is attempted.
  @return 0 on success, -1 on error.
  */
int osrfTransportGroupSendMatch( osrfTransportGroup* grp, transport_message* msg );


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
  Tells the group that a message to the given domain failed
  domain did not make it through;
  @param grp The transport group
  @param comain The failed domain
  */
void osrfTransportGroupSetInactive( osrfTransportGroup* grp, char* domain );


/**
  Finds a node in our list of nodes 
  */
osrfTransportGroupNode* __osrfTransportGroupFindNode( osrfTransportGroup* grp, char* domain );



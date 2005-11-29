#include <sys/select.h>
#include <signal.h>
#include <stdio.h>

#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_list.h"
#include "opensrf/osrf_hash.h"

#include "opensrf/string_array.h"
#include "opensrf/transport_client.h"
#include "opensrf/transport_message.h"

#include "opensrf/osrf_message.h"



/* a router maintains a list of server classes */
struct __osrfRouterStruct {

	osrfHash* classes;	/* our list of server classes */
	char* domain;			/* our login domain */
	char* name;
	char* resource;
	char* password;
	int port;

	osrfStringArray* trustedClients;
	osrfStringArray* trustedServers;

	transport_client* connection;
};

typedef struct __osrfRouterStruct osrfRouter;


/* a class maintains a set of server nodes */
struct __osrfRouterClassStruct {
	osrfRouter* router; /* our router handle */
	osrfHashIterator* itr;
	osrfHash* nodes;
	transport_client* connection;
};
typedef struct __osrfRouterClassStruct osrfRouterClass;

/* represents a link to a single server's inbound connection */
struct __osrfRouterNodeStruct {
	char* remoteId;	/* send message to me via this login */
	int count;			/* how many message have been sent to this node */
	transport_message* lastMessage;
};
typedef struct __osrfRouterNodeStruct osrfRouterNode;

/**
  Allocates a new router.  
  @param domain The jabber domain to connect to
  @param name The login name for the router
  @param resource The login resource for the router
  @param password The login password for the new router
  @param port The port to connect to the jabber server on
  @param trustedClients The array of client domains that we allow to send requests through us
  @param trustedServers The array of server domains that we allow to register, etc. with ust.
  @return The allocated router or NULL on memory error
  */
osrfRouter* osrfNewRouter( char* domain, char* name, char* resource, 
	char* password, int port, osrfStringArray* trustedClients, osrfStringArray* trustedServers );

/**
  Connects the given router to the network
  */
int osrfRouterConnect( osrfRouter* router );

/**
  Waits for incoming data to route
  If this function returns, then the router's connection to the jabber server
  has failed.
  */
void osrfRouterRun( osrfRouter* router );


/**
  Allocates and adds a new router class handler to the router's list of handlers.
  Also connects the class handler to the network at <routername>@domain/<classname>
  @param router The current router instance
  @param classname The name of the class this node handles.
  @return 0 on success, -1 on connection error.
  */
osrfRouterClass* osrfRouterAddClass( osrfRouter* router, char* classname );

/**
  Adds a new server node to the given class.
  @param rclass The Router class to add the node to
  @param remoteId The remote login of this node
  @return 0 on success, -1 on generic error
  */
int osrfRouterClassAddNode( osrfRouterClass* rclass, char* remoteId );


/**
  Handles top level router messages
  @return 0 on success
  */
int osrfRouterHandleMessage( osrfRouter* router, transport_message* msg );


/**
  Handles class level requests
  @return 0 on success
  */
int osrfRouterClassHandleMessage( osrfRouter* router, 
		osrfRouterClass* rclass, transport_message* msg );

/**
  Removes a given class from the router, freeing as it goes
  */
int osrfRouterRemoveClass( osrfRouter* router, char* classname );

/**
  Removes the given node from the class.  Also, if this is that last node in the set,
  removes the class from the router 
  @return 0 on successful removal with no class removal
  @return 1 on successful remove with class removal
  @return -1 error on removal
 */
int osrfRouterClassRemoveNode( osrfRouter* router, char* classname, char* remoteId );

/**
  Frees a router class object
  Takes a void* since it is freed by the hash code
  */
void osrfRouterClassFree( char* classname, void* rclass );

/**
  Frees a router node object 
  Takes a void* since it is freed by the list code
  */
void osrfRouterNodeFree( char* remoteId, void* node );


/**
  Frees a router
  */
void osrfRouterFree( osrfRouter* router );

/**
  Finds the class associated with the given class name in the list of classes
  */
osrfRouterClass* osrfRouterFindClass( osrfRouter* router, char* classname );

/**
  Finds the router node within this class with the given remote id 
  */
osrfRouterNode* osrfRouterClassFindNode( osrfRouterClass* rclass, char* remoteId );


/**
  Clears and populates the provided fd_set* with file descriptors
  from the router's top level connection as well as each of the
  router class connections
  @return The largest file descriptor found in the filling process
  */
int __osrfRouterFillFDSet( osrfRouter* router, fd_set* set );



/**
  Utility method for handling incoming requests to the router
  and making sure the sender is allowed.
  */
void osrfRouterHandleIncoming( osrfRouter* router );

/**
	Utility method for handling incoming requests to a router class,
	makes sure sender is a trusted client
	*/
int osrfRouterClassHandleIncoming( osrfRouter* router, char* classname,  osrfRouterClass* class );

/* handles case where router node is not longer reachable.  copies over the
	data from the last sent message and returns a newly crafted suitable for treating
	as a newly inconing message.  Removes the dead node and If there are no more
	nodes to send the new message to, returns NULL.
	*/
transport_message* osrfRouterClassHandleBounce(
		osrfRouter* router, char* classname, osrfRouterClass* rclass, transport_message* msg );



/**
  handles messages that don't have a 'router_command' set.  They are assumed to
  be app request messages 
  */
int osrfRouterHandleAppRequest( osrfRouter* router, transport_message* msg );


/**
  Handles connects, disconnects, etc.
  */
int osrfRouterHandeStatusMessage( osrfRouter* router, transport_message* msg );


/**
  Handles REQUEST messages 
  */
int osrfRouterHandleRequestMessage( osrfRouter* router, transport_message* msg );



int osrfRouterHandleAppRequest( osrfRouter* router, transport_message* msg );


int osrfRouterRespondConnect( osrfRouter* router, transport_message* msg, osrfMessage* omsg );



int osrfRouterProcessAppRequest( osrfRouter* router, transport_message* msg, osrfMessage* omsg );

int osrfRouterHandleAppResponse( osrfRouter* router, 
		transport_message* msg, osrfMessage* omsg, jsonObject* response );


int osrfRouterHandleMethodNFound( osrfRouter* router, transport_message* msg, osrfMessage* omsg );


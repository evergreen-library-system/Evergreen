#include "opensrf/transport_client.h"

#ifndef OSRF_SYSTEM_H
#define OSRF_SYSTEM_H

/** Connects to jabber.  Returns 1 on success, 0 on failure */
int osrf_system_bootstrap_client(); 

/** Useful for managing multiple connections.  Any clients added should
  * live through the duration of the process so there are no cleanup procedures
  * as of yet 
  */
struct transport_client_cache_struct {
	transport_client* client;
	char* service;
	struct transport_client_cache_struct* next;
};
typedef struct transport_client_cache_struct transport_client_cache;

void osrf_system_push_transport_client( transport_client* client, char* service );
transport_client* osrf_system_get_transport_client( char* service );


#endif

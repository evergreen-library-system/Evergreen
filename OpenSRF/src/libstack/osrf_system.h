#ifndef OSRF_SYSTEM_H
#define OSRF_SYSTEM_H

#include "opensrf/transport_client.h"
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "osrf_settings.h"
#include "osrfConfig.h"


/** Connects to jabber.  Returns 1 on success, 0 on failure 
	contextnode is the location in the config file where we collect config info
*/


int osrf_system_bootstrap_client( char* config_file, char* contextnode );

/* bootstraps a client adding the given resource string to the host/pid, etc. resource string */
int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource );

transport_client* osrf_system_get_transport_client();

/* disconnects and destroys the current client connection */
int osrf_system_disconnect_client();
int osrf_system_shutdown(); 

char* osrf_get_config_context();

char* osrf_get_bootstrap_config();

#endif

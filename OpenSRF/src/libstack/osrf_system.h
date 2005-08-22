#include "opensrf/transport_client.h"
#include "utils.h"
#include "logging.h"
#include "osrf_config.h"

#ifndef OSRF_SYSTEM_H
#define OSRF_SYSTEM_H

/** Connects to jabber.  Returns 1 on success, 0 on failure 
	contextnode is the location in the config file where we collect config info
*/

char* osrf_config_context;

int osrf_system_bootstrap_client( char* config_file, char* contextnode );
transport_client* osrf_system_get_transport_client();

int osrf_system_shutdown(); 


#endif

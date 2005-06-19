#include "opensrf/transport_client.h"
#include "utils.h"
#include "logging.h"
#include "osrf_config.h"

#ifndef OSRF_SYSTEM_H
#define OSRF_SYSTEM_H

/** Connects to jabber.  Returns 1 on success, 0 on failure */
int osrf_system_bootstrap_client(); 
transport_client* osrf_system_get_transport_client();

int osrf_system_shutdown(); 

#endif

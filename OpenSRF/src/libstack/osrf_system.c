#include "opensrf/osrf_system.h"


int osrf_system_bootstrap_client() {
	// XXX config values 
	transport_client* client = client_init( "judy", 5222, 0 );
	char buf[256];
	memset(buf,0,256);
	char* host = getenv("HOSTNAME");
	sprintf(buf, "client_%s_%d", host, getpid() );
	if(client_connect( client, "system_client","jkjkasdf", buf, 10, AUTH_DIGEST )) {
		/* push ourselves into the client cache */
		osrf_system_push_transport_client( client, "client" );
		return 1;
	}
	return 0;
}

// -----------------------------------------------------------------------------
// Some client caching utility methods
transport_client_cache* client_cache;

void osrf_system_push_transport_client( transport_client* client, char* service ) {
	if(client == NULL || service == NULL) return;
	transport_client_cache* new = (transport_client_cache*) safe_malloc(sizeof(transport_client_cache));
	new->service = strdup(service);
	new->client = client;
	if(client_cache == NULL) 
		client_cache = new;
	else {
		transport_client_cache* tmp = client_cache->next;
		client_cache = new;
		new->next = tmp;
	}
}

transport_client* osrf_system_get_transport_client( char* service ) {
	if(service == NULL) return NULL;
	transport_client_cache* cur = client_cache;
	while(cur != NULL) {
		if( !strcmp(cur->service, service)) 
			return cur->client;
		cur = cur->next;
	}
	return NULL;
}
// -----------------------------------------------------------------------------



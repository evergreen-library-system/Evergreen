#include "osrf_settings.h" 

osrf_host_config* config = NULL;

char* osrf_settings_host_value(char* format, ...) {
	VA_LIST_TO_STRING(format);
	jsonObject* o = jsonObjectFindPath(config->config, VA_BUF);
	char* val = jsonObjectToSimpleString(o);
	jsonObjectFree(o);
	return val;
}

jsonObject* osrf_settings_host_value_object(char* format, ...) {
	VA_LIST_TO_STRING(format);
	return jsonObjectFindPath(config->config, VA_BUF);
}


int osrf_settings_retrieve(char* hostname) {

	if(!config) {

		osrf_app_session* session = osrf_app_client_session_init("opensrf.settings");
		jsonObject* params = jsonNewObject(hostname);
		int req_id = osrf_app_session_make_req( 
			session, params, "opensrf.settings.host_config.get", 1, NULL );
		osrf_message* omsg = osrf_app_session_request_recv( session, req_id, 60 );
		jsonObjectFree(params);

		if(omsg && omsg->_result_content) {
			config = osrf_settings_new_host_config(hostname);
			config->config = jsonObjectClone(omsg->_result_content);
			osrf_message_free(omsg);
		}

		osrf_app_session_request_finish( session, req_id );
		osrf_app_session_destroy( session );

		if(!config)
			return fatal_handler("Unable to load config for host %s", hostname);
	}

	return 0;
}

osrf_host_config* osrf_settings_new_host_config(char* hostname) {
	if(!hostname) return NULL;
	osrf_host_config* c = safe_malloc(sizeof(osrf_host_config));
	c->hostname = strdup(hostname);
	return c;
}

void osrf_settings_free_host_config(osrf_host_config* c) {
	if(!c) c = config;
	if(!c) return;
	free(c->hostname);
	jsonObjectFree(c->config);	
	free(c);
}

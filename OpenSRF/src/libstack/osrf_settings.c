#include "osrf_settings.h" 

osrf_host_config* config = NULL;

char* osrf_settings_host_value(char* format, ...) {

	/* grab the format string ---------------- */
	long len = 0;
	va_list args;
	va_list a_copy;

	va_copy(a_copy, args);

	va_start(args, format);
	len = va_list_size(format, args);
	char buf[len];
	memset(buf, 0, len);

	va_start(a_copy, format);
	vsnprintf(buf, len - 1, format, a_copy);
	va_end(a_copy);
	/* -------------------------------------- */

	object* o = object_find_path(config->config, buf);

	char* val = NULL;
	if(o && o->is_string && o->string_data) {
		val = strdup(o->string_data);
		free_object(o);
	}	

	return val;
}

object* osrf_settings_host_value_object(char* format, ...) {

	/* grab the format string ---------------- */
	long len = 0;
	va_list args;
	va_list a_copy;

	va_copy(a_copy, args);

	va_start(args, format);
	len = va_list_size(format, args);
	char buf[len];
	memset(buf, 0, len);

	va_start(a_copy, format);
	vsnprintf(buf, len - 1, format, a_copy);
	va_end(a_copy);
	/* -------------------------------------- */

	return object_find_path(config->config, buf);
}


int osrf_settings_retrieve(char* hostname) {

	if(!config) {

		osrf_app_session* session = osrf_app_client_session_init("opensrf.settings");
		object* params = new_object(hostname);
		int req_id = osrf_app_session_make_req( session, params, "opensrf.settings.host_config.get", 1, NULL );
		osrf_message* omsg = osrf_app_session_request_recv( session, req_id, 60 );
		free_object(params);

		if(omsg && omsg->_result_content) {
			config = osrf_settings_new_host_config(hostname);
			config->config = object_clone(omsg->_result_content);
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
	free_object(c->config);	
	free(c);
}

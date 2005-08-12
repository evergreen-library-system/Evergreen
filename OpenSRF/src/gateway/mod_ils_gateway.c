#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "apr_compat.h"
#include "apr_strings.h"

/* our stuff */
#include "opensrf/transport_client.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include "opensrf/string_array.h"
#include "md5.h"
#include "objson/object.h"
#include "objson/json_parser.h"

#ifdef RESTGATEWAY
#include "rest_xml.h"

#define MODULE_NAME "ils_rest_gateway_module"
#else
#define MODULE_NAME "ils_gateway_module"
#endif


static void mod_ils_gateway_child_init(apr_pool_t *p, server_rec *s) {
	if( ! osrf_system_bootstrap_client( "/openils/conf/gateway.xml") ) 
		fatal_handler("Unable to load gateway config file...");
	fprintf(stderr, "Bootstrapping %d\n", getpid() );
	fflush(stderr);
}

static int mod_ils_gateway_method_handler (request_rec *r) {


	/* make sure we're needed first thing*/
	if (strcmp(r->handler, MODULE_NAME )) 
		return DECLINED;


	apr_pool_t *p = r->pool;	/* memory pool */
	char* arg = r->args;			/* url query string */

	char* service					= NULL;	/* service to connect to */
	char* method					= NULL;	/* method to perform */

	//json* exception				= NULL; /* returned in error conditions */
	object* exception				= NULL; /* returned in error conditions */
	string_array* sarray			= init_string_array(12); /* method parameters */

	growing_buffer* buffer		= NULL;	/* POST data */
	growing_buffer* tmp_buf		= NULL;	/* temp buffer */

	char* key						= NULL;	/* query item name */
	char* val						= NULL;	/* query item value */



	/* verify we are connected */
	if(!osrf_system_get_transport_client()) {
		fatal_handler("Bootstrap Failed, no transport client");
		return HTTP_INTERNAL_SERVER_ERROR;
	}



	/* gather the post args and append them to the url query string */
	if( !strcmp(r->method,"POST") ) {

		ap_setup_client_block(r,REQUEST_CHUNKED_DECHUNK);

		if(! ap_should_client_block(r)) {
			warning_handler("No Post Body");
		}

		char body[1025];
		memset(body,0,1025);
		buffer = buffer_init(1025);

		while(ap_get_client_block(r, body, 1024)) {
			debug_handler("Apache read POST block data: %s\n", body);
			buffer_add( buffer, body );
			memset(body,0,1025);
		}

		if(arg && arg[0]) {
			tmp_buf = buffer_init(1024);
			buffer_add(tmp_buf,arg);
			buffer_add(tmp_buf,buffer->buf);
			arg = (char*) apr_pstrdup(p, tmp_buf->buf);
			buffer_free(tmp_buf);
		} else {
			arg = (char*) apr_pstrdup(p, buffer->buf);
		}
		buffer_free(buffer);

	} 

	debug_handler("params args are %s", arg);


	if( ! arg || !arg[0] ) { /* we received no request */
		warning_handler("No Args");
		return OK;
	}

	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);

	
	while( arg && (val = ap_getword(p, (const char**) &arg, '&'))) {

		key = ap_getword(r->pool, (const char**) &val, '=');
		if(!key || !key[0])
			break;

		ap_unescape_url((char*)key);
		ap_unescape_url((char*)val);

		if(!strcmp(key,"service")) 
			service = val;

		if(!strcmp(key,"method"))
			method = val;

		if(!strcmp(key,"param"))
			string_array_add(sarray, val);

	}

	info_handler("Performing(%d):  service %s | method %s | \n",
			getpid(), service, method );

	int k;
	for( k = 0; k!= sarray->size; k++ ) {
		info_handler( "param %s", string_array_get_string(sarray,k));
	}

	osrf_app_session* session = osrf_app_client_session_init(service);

	debug_handler("MOD session service: %s", session->remote_service );

	int req_id = osrf_app_session_make_req( session, NULL, method, 1, sarray );
	string_array_destroy(sarray);

	osrf_message* omsg = NULL;

	growing_buffer* result_data = buffer_init(256);
	buffer_add(result_data, "[");

	/* gather result data */
	while((omsg = osrf_app_session_request_recv( session, req_id, 60 ))) {

		if( omsg->_result_content ) {
			char* content = object_to_json(omsg->_result_content);
			buffer_add(result_data, content);
			buffer_add( result_data, ",");
			free(content);

		} else {


			/* build the exception information */
			growing_buffer* exc_buffer = buffer_init(256);
			buffer_add( exc_buffer, "\nReceived Exception:\nName: " );
			buffer_add( exc_buffer, omsg->status_name );
			buffer_add( exc_buffer, "\nStatus: " );
			buffer_add( exc_buffer, omsg->status_text );
			buffer_add( exc_buffer, "\nStatus: " );

			char code[16];
			memset(code, 0, 16);
			sprintf( code, "%d", omsg->status_code );
			buffer_add( exc_buffer, code );

			exception = json_parse_string("{}");
			exception->add_key(exception, "is_err", json_parse_string("1"));
			exception->add_key(exception, "err_msg", new_object(exc_buffer->buf) );

			warning_handler("*** Looks like we got a "
					"server exception\n%s", exc_buffer->buf );

			buffer_free(exc_buffer);
			osrf_message_free(omsg);
			break;
		}

		osrf_message_free(omsg);
		omsg = NULL;
	}

	/* remove trailing comma */
	if( result_data->buf[strlen(result_data->buf)-1] == ',') {
		result_data->buf[strlen(result_data->buf)-1] = '\0';
		result_data->n_used--;
	}

	buffer_add(result_data,"]");

	char* content = NULL;

	/* round up our data */
	if(exception) {
		content = strdup(exception->to_json(exception));
		free_object(exception);
	} else {

#ifdef RESTGATEWAY
		/* set content type to text/xml for passing around XML objects */
		ap_set_content_type(r, "text/xml");
		content = json_string_to_xml( buffer_data(result_data) );
#else
		/* set content type to text/plain for passing around JSON objects */
		ap_set_content_type(r, "text/plain");
		content = buffer_data(result_data); 
#endif
	}
	

	buffer_free(result_data);

	if(content) {
		debug_handler( "APACHE writing data to web client: %s", content );
		ap_rputs(content,r);
		free(content);
	} 

	osrf_app_session_request_finish( session, req_id );
	debug_handler("gateway process message successfully");


	osrf_app_session_destroy(session);
	return OK;

}

/*
 * This function is a callback and it declares what other functions
  * should be called for request processing and configuration requests.
   * This callback function declares the Handlers for other events.  */
static void mod_ils_gateway_register_hooks (apr_pool_t *p) {
// I think this is the call to make to register a handler for method calls (GET PUT et. al.).
// We will ask to be last so that the comment has a higher tendency to
// go at the end.
	ap_hook_handler(mod_ils_gateway_method_handler, NULL, NULL, APR_HOOK_MIDDLE);
	ap_hook_child_init(mod_ils_gateway_child_init,NULL,NULL,APR_HOOK_MIDDLE);
}

/*
 * Declare and populate the module's data structure.  The
  * name of this structure ('tut1_module') is important - it
   * must match the name of the module.  This structure is the
 * only "glue" between the httpd core and the module.
  */

#ifdef RESTGATEWAY

module AP_MODULE_DECLARE_DATA ils_rest_gateway_module =
{
STANDARD20_MODULE_STUFF,
NULL,
NULL,
NULL,
NULL,
NULL,
mod_ils_gateway_register_hooks,
};

#else

module AP_MODULE_DECLARE_DATA ils_gateway_module =
{
STANDARD20_MODULE_STUFF,
NULL,
NULL,
NULL,
NULL,
NULL,
mod_ils_gateway_register_hooks,
};

#endif


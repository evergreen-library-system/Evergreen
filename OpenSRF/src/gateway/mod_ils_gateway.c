/*
Copyright 2002 Kevin O'Donnell

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

/*
 * Include the core server components.
  */
#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "apr_compat.h"
#include "apr_strings.h"



/* our stuff */
#include "opensrf/transport_client.h"
#include "opensrf/generic_utils.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include "md5.h"

/*
 * This function is registered as a handler for HTTP methods and will
  * therefore be invoked for all GET requests (and others).  Regardless
   * of the request type, this function simply sends a message to
 * STDERR (which httpd redirects to logs/error_log).  A real module
  * would do *alot* more at this point.
   */
#define MODULE_NAME "ils_gateway_module"


static void mod_ils_gateway_child_init(apr_pool_t *p, server_rec *s) {
	if( ! osrf_system_bootstrap_client( 
		"/pines/cvs/ILS/OpenSRF/src/gateway/gateway.xml") ) { /* config option */
	}
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

	json* params					= NULL;	/* method parameters */ 
	json* exception				= NULL; /* returned in error conditions */

	growing_buffer* buffer		= NULL;	/* POST data */
	growing_buffer* tmp_buf		= NULL;	/* temp buffer */

	char* key						= NULL;	/* query item name */
	char* val						= NULL;	/* query item value */



	/* verify we are connected */
	if(!osrf_system_get_transport_client()) {
		fatal_handler("Bootstrap Failed, no transport client");
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	/* set content type to text/plain for passing around JSON objects */
	ap_set_content_type(r, "text/plain");



	/* gather the post args and append them to the url query string */
	if( !strcmp(r->method,"POST") ) {

		ap_setup_client_block(r,REQUEST_CHUNKED_DECHUNK);

		if(! ap_should_client_block(r)) {
			warning_handler("No Post Body");
		}

		char body[1024];
		memset(body,0,1024);
		buffer = buffer_init(1024);

		while(ap_get_client_block(r, body, 1024)) {
			buffer_add( buffer, body );
			memset(body,0,1024);
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


	if( ! arg || !arg[0] ) { /* we received no request */
		warning_handler("No Args");
		return OK;
	}

	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);

	
	char* argcopy = (char*) apr_pstrdup(p, arg);

	params = json_object_new_array();;
	while( argcopy && (val = ap_getword(p, &argcopy, '&'))) {

		key = ap_getword(r->pool,&val, '=');
		if(!key || !key[0])
			break;

		ap_unescape_url((char*)key);
		ap_unescape_url((char*)val);

		if(!strcmp(key,"service")) 
			service = val;

		if(!strcmp(key,"method"))
			method = val;

		if(!strcmp(key,"__param"))
			json_object_array_add( params, json_tokener_parse(val));
	}

	debug_handler("Performing(%d):  service %s | method %s | \nparams %s\n\n",
			getpid(), service, method, json_object_to_json_string(params));

	osrf_app_session* session = osrf_app_client_session_init(service);

	/* connect to the remote service */
	if(!osrf_app_session_connect(session)) {
		exception = json_object_new_object();
		json_object_object_add( exception, "is_err", json_object_new_int(1));
		json_object_object_add( exception, 
				"err_msg", json_object_new_string("Unable to connect to remote service"));

		ap_rputs(json_object_to_json_string(exception), r );
		json_object_put(exception);
		return OK;
	}

	int req_id = osrf_app_session_make_request( session, params, method, 1 );
	json_object_put(params);

	osrf_message* omsg = NULL;

	growing_buffer* result_data = buffer_init(256);
	buffer_add(result_data, "[");

	/* gather result data */
	while((omsg = osrf_app_session_request_recv( session, req_id, 20 ))) {

		if( omsg->result_string ) {
			buffer_add(result_data, omsg->result_string);
			debug_handler( "Received Response: %s", omsg->result_string );
			buffer_add( result_data, ",");

		} else {

			warning_handler("*** Looks like we got an exception\n" );

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

			/* build the exception object */
			exception = json_object_new_object();
			json_object_object_add( exception, "is_err", json_object_new_int(1));
			json_object_object_add( exception, 
					"err_msg", json_object_new_string(exc_buffer->buf));
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
		content = strdup(json_object_to_json_string(exception));
		json_object_put(exception);
	} else 
		content = buffer_data(result_data); 
	

	buffer_free(result_data);

	if(content) {
		ap_rputs(content,r);
		free(content);
	} 

	osrf_app_session_request_finish( session, req_id );
	osrf_app_session_disconnect( session );
	osrf_app_session_destroy(session); //need to test removing this

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


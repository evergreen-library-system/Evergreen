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
#include "opensrf/string_array.h"
#include "md5.h"

/*
 * This function is registered as a handler for HTTP methods and will
  * therefore be invoked for all GET requests (and others).  Regardless
   * of the request type, this function simply sends a message to
 * STDERR (which httpd redirects to logs/error_log).  A real module
  * would do *alot* more at this point.
   */
#define MODULE_NAME "ils_gateway_module"

struct session_list_struct {
	//char* service;
	osrf_app_session* session;
	struct session_list_struct* next;
	int serve_count;
};
typedef struct session_list_struct session_list;

/* the global session cache */
static session_list* the_list = NULL;

static void del_session( char* service ) {
	if(!service || ! the_list)
		return;
	
	debug_handler("In del_sesion for %s", service );
	session_list* prev = the_list;
	session_list* item = prev->next;

	if(!strcmp(prev->session->remote_service, service)) {
		info_handler("Removing gateway session for %s", service );
		the_list = item;
		osrf_app_session_destroy(prev->session);
		free(prev);
		return;
	}

	while(item) {
		if( !strcmp(item->session->remote_service, service)) {
			info_handler("Removing gateway session for %s", service );
			prev->next = item->next;
			osrf_app_session_destroy(item->session);
			free(item);
			return;
		}
		prev = item;
		item = item->next;
	}

	warning_handler("Attempt to remove gateway session "
			"that does not exist: %s", service );

}

/* find a session in the list */
/* if(update) we add 1 to the serve_count */
static osrf_app_session* find_session( char* service, int update ) {

	session_list* item = the_list;
	while(item) {

		if(!strcmp(item->session->remote_service,service)) {
			if(update) { 
				if( item->serve_count++ > 20 ) {
					debug_handler("Disconnected session on 20 requests => %s", service);
					osrf_app_session_disconnect(item->session);
					del_session(service);
					return NULL;
					//item->serve_count = 0;
				}
			}
			debug_handler("Found session for %s in gateway cache", service);
			return item->session;
		}

		item = item->next;
	}
	return NULL;
}

/* add a session to the list */
static void add_session( char* service, osrf_app_session* session ) {

	if(!session) return;

	if(find_session(service,0))
		return;

	debug_handler("Add session for %s to the cache", service );

	session_list* new_item = (session_list*) safe_malloc(sizeof(session_list));
	new_item->session = session;
	//new_item->service = service;
	new_item->serve_count = 0;

	if(the_list) {
		session_list* second = the_list->next;
		the_list = new_item;
		new_item->next = second;
	} else {
		the_list = new_item;
	}
}

static void mod_ils_gateway_child_init(apr_pool_t *p, server_rec *s) {
	if( ! osrf_system_bootstrap_client( 
		"/pines/cvs/ILS/OpenSRF/src/gateway/gateway.xml") ) { /* config option */
	}

	/* we don't want to waste time parsing json that we're not going to look at*/
	osrf_message_set_json_parse_result(0);
	osrf_message_set_json_parse_params(0);
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

	json* exception				= NULL; /* returned in error conditions */
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
			string_array_add(sarray, val);

	}

	info_handler("Performing(%d):  service %s | method %s | \n",
			getpid(), service, method );

	int k;
	for( k = 0; k!= sarray->size; k++ ) {
		info_handler( "param %s", string_array_get_string(sarray,k));
	}

	osrf_app_session* session = find_session(service,1);

	if(!session) {
		debug_handler("building new session for %s", service );
		session = osrf_app_client_session_init(service);
		add_session(service, session);
	}

	debug_handler("MOD session service: %s", session->remote_service );


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

	int req_id = osrf_app_session_make_request( session, NULL, method, 1, sarray );
	string_array_destroy(sarray);

	osrf_message* omsg = NULL;

	growing_buffer* result_data = buffer_init(256);
	buffer_add(result_data, "[");

	/* gather result data */
	while((omsg = osrf_app_session_request_recv( session, req_id, 30 ))) {

		if( omsg->result_string ) {
			buffer_add(result_data, omsg->result_string);
			buffer_add( result_data, ",");

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

			/* build the exception object */
			exception = json_object_new_object();
			json_object_object_add( exception, "is_err", json_object_new_int(1));
			json_object_object_add( exception, 
					"err_msg", json_object_new_string(exc_buffer->buf));

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


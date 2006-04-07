#include "apachetools.h"
#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_system.h"
#include "objson/object.h"
#include "objson/json2xml.h"

#define MODULE_NAME "osrf_json_gateway_module"
#define GATEWAY_CONFIG "OSRFGatewayConfig"
#define CONFIG_CONTEXT "gateway"

#define GATEWAY_DEFAULT_CONFIG "/openils/conf/opensrf_core.xml"


/* our config structure */
typedef struct { 
	char* configfile;  /* our bootstrap config file */
} osrf_json_gateway_config;

module AP_MODULE_DECLARE_DATA osrf_json_gateway_module;

char* osrf_json_gateway_config_file = NULL;
int bootstrapped = 0;
int numserved = 0;

static const char* osrf_json_gateway_set_config(cmd_parms *parms, void *config, const char *arg) {
	osrf_json_gateway_config  *cfg;
	cfg = ap_get_module_config(parms->server->module_config, &osrf_json_gateway_module);
	cfg->configfile = (char*) arg;
	osrf_json_gateway_config_file = (char*) arg;
	return NULL;
}

/* tell apache about our commands */
static const command_rec osrf_json_gateway_cmds[] = {
	AP_INIT_TAKE1( GATEWAY_CONFIG, osrf_json_gateway_set_config, 
			NULL, RSRC_CONF, "osrf json gateway config file"),
	{NULL}
};

/* build the config object */
static void* osrf_json_gateway_create_config( apr_pool_t* p, server_rec* s) {
	osrf_json_gateway_config* cfg = (osrf_json_gateway_config*) 
			apr_palloc(p, sizeof(osrf_json_gateway_config));
	cfg->configfile = GATEWAY_DEFAULT_CONFIG;
	return (void*) cfg;
}


static void osrf_json_gateway_child_init(apr_pool_t *p, server_rec *s) {

	char* cfg = osrf_json_gateway_config_file;
	if( ! osrf_system_bootstrap_client( cfg, CONFIG_CONTEXT) ) {
		ap_log_error( APLOG_MARK, APLOG_ERR, 0, s, "Unable to Bootstrap OpenSRF Client..");
		return;
	}
	bootstrapped = 1;
	ap_log_error( APLOG_MARK, APLOG_DEBUG, 0, s, "Bootstrapping OpenSRF Client..");
}

static int osrf_json_gateway_method_handler (request_rec *r) {

	/* make sure we're needed first thing*/
	if (strcmp(r->handler, MODULE_NAME )) return DECLINED;

	/* verify we are connected */
	if( !bootstrapped || !osrf_system_get_transport_client()) {
		ap_log_rerror( APLOG_MARK, APLOG_ERR, 0, r, "Cannot process request "
				"because the OpenSRF JSON gateway has not been bootstrapped...");
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	osrfLogSetAppname("osrf_json_gw");

	char* service		= NULL;	/* service to connect to */
	char* method		= NULL;	/* method to perform */
	char* format		= NULL;	/* method to perform */
	char* a_l			= NULL;	/* request api level */
	int   isXML			= 0;
	int   api_level	= 1;

	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);

	string_array* mparams	= NULL;
	string_array* params		= apacheParseParms(r); /* free me */
	service		= apacheGetFirstParamValue( params, "service" );
	method		= apacheGetFirstParamValue( params, "method" ); 
	format		= apacheGetFirstParamValue( params, "format" ); 
	a_l			= apacheGetFirstParamValue( params, "api_level" ); 
	mparams		= apacheGetParamValues( params, "param" ); /* free me */

	if (a_l)
		api_level = atoi(a_l);

	if (format && !strcasecmp(format, "xml" )) {
		isXML = 1;
		ap_set_content_type(r, "application/xml");
	} else {
		ap_set_content_type(r, "text/plain");
	}


	if( service && method ) {

		osrfLogInfo( OSRF_LOG_MARK,  "service=%s, method=%s", service, method );
		osrfAppSession* session = osrf_app_client_session_init(service);
		int req_id = osrf_app_session_make_req( session, NULL, method, api_level, mparams );
		osrf_message* omsg = NULL;

		int statuscode = 200;

		/* kick off the object */
		if (isXML)
			ap_rputs("<response xmlns=\"http://opensrf.org/-/namespaces/gateway/v1\"><payload>", r);
		else
			ap_rputs("{\"payload\":[", r);

		int morethan1		= 0;
		char* statusname	= NULL;
		char* statustext	= NULL;
		char* output		= NULL;

		while((omsg = osrfAppSessionRequestRecv( session, req_id, 60 ))) {
	
			statuscode = omsg->status_code;
			jsonObject* res;	

			if( ( res = osrfMessageGetResult(omsg)) ) {

				if (isXML) {
					output = jsonObjectToXML( res );
				} else {
					output = jsonObjectToJSON( res );
					if( morethan1 ) ap_rputs(",", r); /* comma between JSON array items */
				}
				ap_rputs(output, r);
				free(output);
				morethan1 = 1;
		
			} else {
	
				if( statuscode > 299 ) { /* the request returned a low level error */
					statusname = omsg->status_name ? strdup(omsg->status_name) : strdup("Unknown Error");
					statustext = omsg->status_text ? strdup(omsg->status_text) : strdup("No Error Message");
					osrfLogError( OSRF_LOG_MARK,  "Gateway received error: %s", statustext );
				}
			}
	
			osrf_message_free(omsg);
			if(statusname) break;
		}

		if (isXML)
			ap_rputs("</payload>", r);
		else
			ap_rputs("]",r); /* finish off the payload array */

		if(statusname) {

			/* add a debug field if the request died */
			ap_log_rerror( APLOG_MARK, APLOG_INFO, 0, r, 
					"OpenSRF JSON Request returned error: %s -> %s", statusname, statustext );
			int l = strlen(statusname) + strlen(statustext) + 32;
			char buf[l];
			bzero(buf,l);

			if (isXML)
				snprintf( buf, l, "<debug>\"%s : %s\"</debug>", statusname, statustext );

			else {
				char bb[l];
				bzero(bb, l);
				snprintf(bb, l,  "%s : %s", statusname, statustext);
				jsonObject* tmp = jsonNewObject(bb);
				char* j = jsonObjectToJSON(tmp);
				snprintf( buf, l, ",\"debug\": %s", j);
				free(j);
				jsonObjectFree(tmp);
			}

			ap_rputs(buf, r);

			free(statusname);
			free(statustext);
		}

		/* insert the status code */
		char buf[32];
		bzero(buf,32);

		if (isXML)
			snprintf(buf, 32, "<status>%d</status>", statuscode );
		else
			snprintf(buf, 32, ",\"status\":%d", statuscode );

		ap_rputs( buf, r );

		if (isXML)
			ap_rputs("</response>", r);
		else
			ap_rputs( "}", r ); /* finish off the object */

		osrf_app_session_destroy(session);
	}

	osrfLogInfo(OSRF_LOG_MARK, "Completed processing service=%s, method=%s", service, method);
	osrfLogDebug(OSRF_LOG_MARK, "Gateway served %d requests", ++numserved);
	string_array_destroy(params);
	string_array_destroy(mparams);

	return OK;
}

static void osrf_json_gateway_register_hooks (apr_pool_t *p) {
	ap_hook_handler(osrf_json_gateway_method_handler, NULL, NULL, APR_HOOK_MIDDLE);
	ap_hook_child_init(osrf_json_gateway_child_init,NULL,NULL,APR_HOOK_MIDDLE);
}


module AP_MODULE_DECLARE_DATA osrf_json_gateway_module = {
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	osrf_json_gateway_create_config,
	NULL,
	osrf_json_gateway_cmds,
	osrf_json_gateway_register_hooks,
};





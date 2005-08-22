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
#include "string_array.h"
#include "md5.h"
#include "objson/object.h"
#include "objson/json_parser.h"

#ifdef RESTGATEWAY
#include "rest_xml.h"
#define GATEWAY_CONFIG "ILSRestGatewayConfig"
#define MODULE_NAME "ils_rest_gateway_module"
#define CONFIG_CONTEXT "rest_gateway"

#else
#define MODULE_NAME "ils_gateway_module"
#define GATEWAY_CONFIG "ILSGatewayConfig"
#define CONFIG_CONTEXT "gateway"
#endif

#define GATEWAY_DEFAULT_CONFIG "/openils/conf/opensrf_core.xml"


/* our config structure */
typedef struct { 
	char* configfile;  /* our bootstrap config file */
} ils_gateway_config;

#ifdef RESTGATEWAY
module AP_MODULE_DECLARE_DATA ils_rest_gateway_module;
#else 
module AP_MODULE_DECLARE_DATA ils_gateway_module;
#endif


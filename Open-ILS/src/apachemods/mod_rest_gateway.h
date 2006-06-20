#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
//#include "apr_compat.h"
#include "apr_strings.h"

/* our stuff */
#include "opensrf/transport_client.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include "string_array.h"
#include "md5.h"
#include "objson/object.h"
#include "objson/json_parser.h"

#include "json_xml.h"
#define GATEWAY_CONFIG "ILSRestGatewayConfig"
#define MODULE_NAME "ils_rest_gateway_module"
#define CONFIG_CONTEXT "gateway"

#define GATEWAY_DEFAULT_CONFIG "/openils/conf/opensrf_core.xml"


/* our config structure */
typedef struct { 
	char* configfile;  /* our bootstrap config file */
} ils_gateway_config;

module AP_MODULE_DECLARE_DATA ils_rest_gateway_module;


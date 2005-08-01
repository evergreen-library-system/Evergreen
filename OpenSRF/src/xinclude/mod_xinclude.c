#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "apr_compat.h"
#include "apr_strings.h"

#include <libxml/parser.h>
#include <libxml/xinclude.h>

#define MODULE_NAME "xinclude_module"

static int mod_xinclude_handler (request_rec *r) {

	/* make sure we're needed first thing*/
	if (strcmp(r->handler, MODULE_NAME )) 
		return DECLINED;

	/* set content type */
	ap_set_content_type(r, "text/html");


	/* which file are we parsing */
	char* file = r->filename;

	if(!file) { 
		fprintf(stderr, "No XML file to parse");
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	/* parse the doc */
	xmlDocPtr doc = xmlParseFile(file);

	if(!doc) {
		fprintf(stderr, "Error parsing XML file %s\n", file);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	/* process the xincludes */
	int status = xmlXIncludeProcess(doc);
	
	if(status < 0) {
		fprintf(stderr, "Error processing XIncludes in  XML file %s\n", file);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	xmlBufferPtr xmlbuf = xmlBufferCreate();
	xmlNodeDump( xmlbuf, doc, xmlDocGetRootElement(doc), 0, 0);
	char* xml = (char*) (xmlBufferContent(xmlbuf));

	ap_rputs(xml,r);

	xmlBufferFree(xmlbuf);
	xmlFreeDoc(doc);

	return OK;
}


static void mod_xinclude_register_hooks (apr_pool_t *p) {
	ap_hook_handler(mod_xinclude_handler, NULL, NULL, APR_HOOK_MIDDLE);
}

module AP_MODULE_DECLARE_DATA xinclude_module = {
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	mod_xinclude_register_hooks,
};


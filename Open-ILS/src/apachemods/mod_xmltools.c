#include "apachetools.h"
#include "xmltools.h"

#define MODULE_NAME		"mod_xmltools" /* our module name */
#define PARAM_LOCALE		"locale"			/* the URL param for the local directory */
#define LANG_DTD			"lang.dtd"		/* the DTD for the test entities */

/* these should be config directives */
#define LOCALE_DIR		"/home/erickson/sandbox/apachemods/locale"		/* The root directory where the local files are stored */
#define DEFAULT_LOCALE	"en-US"			/* If no locale data is provided */


/* Child Init */
static void mod_xmltools_child_init(apr_pool_t *p, server_rec *s) {
}

/* allocates a char* to hold the name of the DTD language file 
	Prints to stderr and returns NULL if there was an error loading the file 
	*/

static char* get_dtd_lang_file(string_array* params) {

	char* localedir = apacheGetFirstParamValue(params, PARAM_LOCALE);
	if(!localedir) localedir = strdup(DEFAULT_LOCALE);

	int len = strlen(LANG_DTD) + strlen(localedir) + strlen(LOCALE_DIR) + 1;
	char dtdfile[len];
	bzero(dtdfile, len);

	if(localedir)
		sprintf(dtdfile, "%s/%s/%s",  LOCALE_DIR, localedir, LANG_DTD );

	return strdup(dtdfile);
}

static int mod_xmltools_handler (request_rec* r) {

	/* make sure we're needed first thing*/
	if (strcmp(r->handler, MODULE_NAME )) 
		return DECLINED;

	/* we accept get/post requests */
	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);

	ap_set_content_type(r, "text/html");

	string_array* params = apacheParseParms(r);

	char* file = r->filename;
	char* dtdfile = get_dtd_lang_file(params);

	xmlDocPtr doc;

	/* be explicit */
	xmlSubstituteEntitiesDefault(0);

	/* parse the doc */
	if( (doc = xmlParseFile(file)) == NULL) {
		fprintf(stderr, "\n ^-- Error parsing XML file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	/* process xincludes */
	if( xmlXIncludeProcess(doc) < 0 ) {
		fprintf(stderr, "\n ^-- Error processing XIncludes for file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}


	/* replace the DTD */
	if(xmlReplaceDtd(doc, dtdfile) < 0) {
		fprintf(stderr, "Error replacing DTD file with file %s\n", dtdfile);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}


	/* force DTD entity replacement */
	doc = xmlProcessDtdEntities(doc);

	/* stringify */
	char* xml = xmlDocToString(doc, 0);

	/* print the doc */
	ap_rputs(xml, r);

	/* deallocate */
	free(dtdfile);
	free(xml);
	xmlFreeDoc(doc);
	xmlCleanupCharEncodingHandlers();
	xmlCleanupParser();
	
	return OK;

}


static void mod_xmltools_register_hooks (apr_pool_t *p) {
	ap_hook_handler(mod_xmltools_handler, NULL, NULL, APR_HOOK_MIDDLE);
	ap_hook_child_init(mod_xmltools_child_init,NULL,NULL,APR_HOOK_MIDDLE);
}

module AP_MODULE_DECLARE_DATA mod_xmltools = {
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	mod_xmltools_register_hooks,
};


#include "mod_xmltools.h"


/* Configuration handlers -------------------------------------------------------- */
static const char* mod_xmltools_set_locale_dir(cmd_parms *parms, void *config, const char *arg) {
	mod_xmltools_config  *cfg = ap_get_module_config(parms->server->module_config, &mod_xmltools);
	cfg->locale_dir = (char*) arg;
	return NULL;
}

static const char* mod_xmltools_set_default_locale(cmd_parms *parms, void *config, const char *arg) {
	mod_xmltools_config *cfg = ap_get_module_config(parms->server->module_config, &mod_xmltools);
	cfg->default_locale = (char*) arg;
	return NULL;
}

static const char* mod_xmltools_set_pre_xsl(cmd_parms *parms, void *config, const char *arg) {
	mod_xmltools_config *cfg = ap_get_module_config(parms->server->module_config, &mod_xmltools);
	cfg->pre_xsl = xsltParseStylesheetFile( (xmlChar*) arg );
	if(cfg->pre_xsl == NULL) {
		fprintf(stderr, "Unable to parse PreXSL stylesheet %s\n", (char*) arg );
		fflush(stderr);
	}
	return NULL;
}

static const char* mod_xmltools_set_post_xsl(cmd_parms *parms, void *config, const char *arg) {
	mod_xmltools_config *cfg = ap_get_module_config(parms->server->module_config, &mod_xmltools);
	cfg->post_xsl = xsltParseStylesheetFile( (xmlChar*) arg );
	if(cfg->post_xsl == NULL) {
		fprintf(stderr, "Unable to parse PostXSL stylesheet %s\n", (char*) arg );
		fflush(stderr);
	}
	return NULL;
}

/* tell apache about our commands */
static const command_rec mod_xmltools_cmds[] = {
	AP_INIT_TAKE1( CONFIG_LOCALE, mod_xmltools_set_default_locale, NULL, RSRC_CONF, "default locale"),
	AP_INIT_TAKE1( CONFIG_LOCALE_DIR, mod_xmltools_set_locale_dir, NULL, RSRC_CONF, "locale directory"),
	AP_INIT_TAKE1( CONFIG_PRE_XSL, mod_xmltools_set_pre_xsl, NULL, RSRC_CONF, "pre xsl"),
	AP_INIT_TAKE1( CONFIG_POST_XSL, mod_xmltools_set_post_xsl, NULL, RSRC_CONF, "post xsl"),
	{NULL}
};

/* build the config object */
static void* mod_xmltools_create_config( apr_pool_t* p, server_rec* s) {
	mod_xmltools_config* cfg = 
		(mod_xmltools_config*) apr_palloc(p, sizeof(mod_xmltools_config));
	cfg->default_locale = DEFAULT_LOCALE;
	cfg->locale_dir = DEFAULT_LOCALE_DIR;
	return (void*) cfg;
}


/* Child Init handler  ----------------------------------------------------------- */
static void mod_xmltools_child_init(apr_pool_t *p, server_rec *s) {
}


/* Request handler  -------------------------------------------------------------- */
static int mod_xmltools_handler (request_rec* r) {

	/* make sure we're needed first thing*/
	if (strcmp(r->handler, MODULE_NAME )) 
		return DECLINED;

	mod_xmltools_config *cfg = ap_get_module_config(r->server->module_config, &mod_xmltools);
	char* locale_dir = cfg->locale_dir;
	char* default_locale = cfg->default_locale;
	xsltStylesheetPtr pre_xsl = cfg->pre_xsl;
	xsltStylesheetPtr post_xsl = cfg->post_xsl;

	/* we accept get/post requests */
	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);

	ap_set_content_type(r, "text/html");

	string_array* params = apacheParseParms(r);

	char* file = r->filename;
	char* dtdfile = get_dtd_lang_file(params, default_locale, locale_dir );

	xmlDocPtr doc;

	/* be explicit */
	xmlSubstituteEntitiesDefault(0);

	/* parse the doc */
	if( (doc = xmlParseFile(file)) == NULL) {
		fprintf(stderr, "\n ^-- Error parsing XML file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	fflush(stderr);

	if(pre_xsl) {
		xmlDocPtr newdoc;
		newdoc = xsltApplyStylesheet(pre_xsl, doc, NULL );
		if(newdoc == NULL) {
			fprintf(stderr, "Error applying PreXSL stylesheet\n");
			fflush(stderr);
		}
		xmlFreeDoc(doc);
		doc = newdoc;
	}

	/* process xincludes */
	if( xmlXIncludeProcess(doc) < 0 ) {
		fprintf(stderr, "\n ^-- Error processing XIncludes for file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	fflush(stderr);

	/* replace the DTD */
	if(xmlReplaceDtd(doc, dtdfile) < 0) {
		fprintf(stderr, "Error replacing DTD file with file %s\n", dtdfile);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}


	/* force DTD entity replacement */
	doc = xmlProcessDtdEntities(doc);

	if(post_xsl) {
		xmlDocPtr newdoc;
		newdoc = xsltApplyStylesheet(post_xsl, doc, NULL );
		if(newdoc == NULL) {
			fprintf(stderr, "Error applying PostXSL stylesheet\n");
			fflush(stderr);
		}
		xmlFreeDoc(doc);
		doc = newdoc;
	}

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


/* register callbacks */
static void mod_xmltools_register_hooks (apr_pool_t *p) {
	ap_hook_handler(mod_xmltools_handler, NULL, NULL, APR_HOOK_MIDDLE);
	ap_hook_child_init(mod_xmltools_child_init,NULL,NULL,APR_HOOK_MIDDLE);
}


/* finally, flesh the module */
module AP_MODULE_DECLARE_DATA mod_xmltools = {
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	mod_xmltools_create_config,
	NULL,
	mod_xmltools_cmds,
	mod_xmltools_register_hooks,
};



/* UTILITY FUNCTIONS ----------------------------------------------------- */
char* get_dtd_lang_file(string_array* params, char* default_locale, char* locale_dir) {

	/* if no locale is provided via URL, we use the default */
	char* locale = apacheGetFirstParamValue(params, PARAM_LOCALE);
	if(!locale) locale = default_locale;
	if(!locale) return NULL;

	int len = strlen(LANG_DTD) + strlen(locale) + strlen(locale_dir) + 1;
	char dtdfile[len];
	bzero(dtdfile, len);

	if(locale)
		sprintf(dtdfile, "%s/%s/%s",  locale_dir, locale, LANG_DTD );

	return strdup(dtdfile);
}



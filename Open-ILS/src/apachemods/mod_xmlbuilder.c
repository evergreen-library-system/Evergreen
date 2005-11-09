#include "mod_xmlbuilder.h"

char* __xmlBuilderDynamicLocale	= NULL;


/* set the base DTD directory */
static const char* xmlBuilderSetBaseDir(cmd_parms *params, void *cfg, const char *arg) {
	xmlBuilderConfig* config = ap_get_module_config(
		params->server->module_config, &xmlbuilder_module );
	config->baseDir = (char*) arg;
	return NULL;
}

static const char* xmlBuilderSetDefaultLocale(
					 cmd_parms* params, void* cfg, const char* arg ) {
	xmlBuilderConfig* config = ap_get_module_config(
		params->server->module_config, &xmlbuilder_module );
	config->defaultLocale = (char*) arg;
	return NULL;
}

static const char* xmlBuilderSetDefaultDtd(
					 cmd_parms* params, void* cfg, const char* arg ) {
	xmlBuilderConfig* config = ap_get_module_config(
		params->server->module_config, &xmlbuilder_module );
	config->defaultDtd = (char*) arg;
	return NULL;
}


static const char* xmlBuilderSetLocaleParam(
					 cmd_parms* params, void* cfg, const char* arg ) {
	xmlBuilderConfig* config = ap_get_module_config(
		params->server->module_config, &xmlbuilder_module );
	config->localeParam = (char*) arg;
	return NULL;
}


static const char* xmlBuilderSetPostXSL(
					 cmd_parms* params, void* cfg, const char* arg ) {
	xmlBuilderConfig* config = ap_get_module_config(
		params->server->module_config, &xmlbuilder_module );
	config->postXSL = xsltParseStylesheetFile((xmlChar*) arg);
	if( config->postXSL == NULL ) 
		apacheDebug("Unable to parse postXSL stylesheet: %s.  No postXSL will be performed", arg);	
	return NULL;
}

static const command_rec xmlBuilderCommands[] = {
	AP_INIT_TAKE1( MODXMLB_CONFIG_LOCALE, 
			xmlBuilderSetDefaultLocale, NULL, ACCESS_CONF, "Default Locale"),
	AP_INIT_TAKE1( MODXMLB_CONFIG_BASE_DIR, 
			xmlBuilderSetBaseDir, NULL, ACCESS_CONF, "Base Directory"),
	AP_INIT_TAKE1( MODXMLB_CONFIG_POST_XSL, 
			xmlBuilderSetPostXSL, NULL, ACCESS_CONF, "Post XSL"),
	AP_INIT_TAKE1( MODXMLB_CONFIG_DEFAULT_DTD, 
			xmlBuilderSetDefaultDtd, NULL, ACCESS_CONF, "Default DTD"),
	AP_INIT_TAKE1( MODXMLB_CONFIG_LOCALE_PARAM,
			xmlBuilderSetLocaleParam, NULL, ACCESS_CONF, "Default DTD"),
	{NULL}
};

static void* xmlBuilderCreateConfig( apr_pool_t* p, server_rec* s ) {
	xmlBuilderConfig* config = 
		(xmlBuilderConfig*) apr_palloc( p, sizeof(xmlBuilderConfig) );
	config->baseDir			= MODXMLB_DEFAULT_BASE_DIR;
	config->defaultLocale	= MODXMLB_DEFAULT_LOCALE;
	config->defaultDtd		= NULL;
	config->postXSL			= NULL;
	config->localeParam		= MODXMLB_DEFAULT_LOCALE_PARAM;
	return (void*) config;
}


/* Child Init handler  ----------------------------------------------------------- */
static void xmlBuilderChildInit( apr_pool_t *p, server_rec *s ) {
}

static int xmlBuilderHandler( request_rec* r ) {

	if( strcmp(r->handler, MODULE_NAME ) ) return DECLINED;

	xmlBuilderConfig* config = ap_get_module_config( 
			r->server->module_config, &xmlbuilder_module );
	
	r->allowed |= (AP_METHOD_BIT << M_GET);
	r->allowed |= (AP_METHOD_BIT << M_POST);
	ap_set_content_type(r, "text/html; charset=utf-8");

	string_array* params = apacheParseParms(r);
	char* locale = apacheGetFirstParamValue(params, config->localeParam);
	if(locale) __xmlBuilderDynamicLocale = locale;
	char* XMLFile = r->filename;

	apacheDebug("Processing file %s", XMLFile);
	xmlDocPtr doc = xmlBuilderProcessFile( XMLFile, config );
	if(!doc) return apacheError( "Unable to parse XML file %s", XMLFile );

	/* apply the post XSL */
	if(config->postXSL) {
		xmlDocPtr newdoc;
		newdoc = xsltApplyStylesheet(config->postXSL, doc, NULL );

		if(newdoc == NULL) {
			apacheDebug("Error applying postXSL... skipping.");
		} else {
			xmlFreeDoc(doc);
			doc = newdoc;
		}
	}

	char* docXML = xmlDocToString( doc, 1 );
	ap_rputs(docXML, r);
	free(docXML);
	xmlFreeDoc( doc );
	doc = NULL;
	xmlCleanupCharEncodingHandlers();
	xmlCleanupParser();

	return OK;
}


/* frees the collected DTD's */
static void __xmlBuilderFreeDtdHash( char* key, void* item ) {
	if(!item) return;
	xmlFreeDtd( item );
}


xmlDocPtr xmlBuilderProcessFile( char* filename, xmlBuilderConfig* config ) {
	if(!filename) { 
		apacheError( "No XML file provided" ); return NULL; }

	xmlBuilderContext context;
	context.config		= config;
	context.doc			= xmlNewDoc( BAD_CAST "1.0" );
	context.dtdHash	= osrfNewHash();
	context.entHash	= osrfNewHash();
	context.nodeList	= osrfNewList();
	context.xmlError	= 0;
	context.xmlFile	= filename;
	context.dtdHash->freeItem = &__xmlBuilderFreeDtdHash;

	/* pre-parse the default dtd if defined */
	if( config->defaultDtd ) 
		xmlBuilderAddDtd( config->defaultDtd, &context );

	xmlParserCtxtPtr parserCtx;

	parserCtx = xmlCreatePushParserCtxt(xmlBuilderSaxHandler, &context, "", 0, NULL);
	xmlCtxtReadFile( parserCtx, filename, NULL, XML_PARSE_RECOVER );

	xmlFreeParserCtxt( parserCtx );
	osrfListFree(context.nodeList);
	osrfHashFree(context.entHash);
	osrfHashFree(context.dtdHash);
	return context.doc;
}


void xmlBuilderStartElement( void* context, const xmlChar *name, const xmlChar **atts ) {
	apacheDebug( "Starting element: %s", name );
	xmlBuilderContext* ctx = (xmlBuilderContext*) context;

	xmlNodePtr node = NULL;

	/* process xincludes as a sub-doc */
	if( !strcmp( name, "xi:include" ) ) { 

		char* href = strdup(xmlSaxAttr( atts, "href" ));
		if(href) {

			/* find the relative path for the xinclude */
			if(href[0] != '/') {
				int len = strlen(ctx->xmlFile) + strlen(href) + 1;
				char buf[len];
				bzero(buf, len);
				strcpy( buf, ctx->xmlFile );
				int i;
				for( i = strlen(buf); i != 0; i-- ) {
					if( buf[i] == '/' ) break;
					buf[i] = '\0';
				}
				strcat( buf, href );
				free(href);
				href = strdup(buf);
			}


			apacheDebug( "Processing xinclude %s", href );
			xmlDocPtr subDoc = xmlBuilderProcessFile( href, ctx->config );
			node = xmlDocGetRootElement( subDoc );
		}

		if(!node) {
			apacheError("Unable to parse xinclude: %s", href );
			free(href);
			return;
		}
		free(href);

	} else {
		node = xmlNewNode(NULL, name);
		xmlAddAttrs( node, atts );
	}


	xmlNodePtr parent = osrfListGetIndex( 
			ctx->nodeList, ctx->nodeList->size - 1 );

	if( parent ) xmlAddChild( parent, node );
	else xmlDocSetRootElement(ctx->doc, node);
	
	osrfListPush( ctx->nodeList, node );
}

void xmlBuilderEndElement( void* context, const xmlChar* name ) {
	xmlBuilderContext* ctx = (xmlBuilderContext*) context;
	osrfListPop( ctx->nodeList );
}


void xmlBuilderHandleCharacter(void* context, const xmlChar *ch, int len) {
	xmlBuilderContext* ctx = (xmlBuilderContext*) context;
	xmlNodePtr node = osrfListGetIndex( 
			ctx->nodeList, ctx->nodeList->size - 1 );

	if(node) {
		xmlNodePtr txt = xmlNewTextLen(ch, len);
		xmlAddChild( node, txt );
	}

}


void xmlBuilderParseError( void* context, const char* msg, ... ) {
	xmlBuilderContext* ctx = (xmlBuilderContext*) context;
	VA_LIST_TO_STRING(msg);
	apacheDebug( "Parser Error Occurred: %s", VA_BUF);
	ctx->xmlError = 1;
}


xmlEntityPtr xmlBuilderGetEntity( void* context, const xmlChar* name ) {
	xmlBuilderContext* ctx = (xmlBuilderContext*) context;
	return osrfHashGet( ctx->entHash, name );
}


void xmlBuilderExtSubset( void* blob, 
		const xmlChar* name, const xmlChar* extId, const xmlChar* sysId ) {

	xmlBuilderContext* context = (xmlBuilderContext*) blob;
	if( context->config->defaultDtd ) return; /* only use the default if defined */
	xmlBuilderAddDtd( sysId, context );
}



void xmlBuilderAddDtd( const char* sysId, xmlBuilderContext* context ) {

	if(!sysId) return;
	if( osrfHashGet( context->dtdHash, sysId ) ) return; /* already parsed this hash */

	/* use the dynamic locale if defined... default locale instead */
	char* locale;
	if(__xmlBuilderDynamicLocale) locale = __xmlBuilderDynamicLocale;
	else locale = context->config->defaultLocale;

	/* determine the path to the DTD file and load it */
	int len = strlen(context->config->baseDir) + strlen(locale) + strlen(sysId) + 4;
	char buf[len]; bzero(buf,len);
	snprintf( buf, len, "%s/%s/%s", context->config->baseDir, locale, sysId );

	apacheDebug("Parsing DTD file %s", buf);
	xmlDtdPtr dtd = xmlParseDTD(NULL, buf);


	/* cycle through entities and push them into the entity hash */
	xmlNodePtr node = dtd->children;
	while( node ) {
		if( node->type == XML_ENTITY_DECL ) { /* shove the entities into the hash */
			xmlEntityPtr ent = (xmlEntityPtr) node;
			osrfHashSet( context->entHash, ent, (char*) ent->name );
		}
		node = node->next;
	}

	/* cache the DTD so we can free it later */
	osrfHashSet( context->dtdHash, dtd, sysId );
}


/* ------------------------------------------------------------------------ */

/* register callbacks */
static void xmlBuilderRegisterHooks (apr_pool_t *p) {
	ap_hook_handler(xmlBuilderHandler, NULL, NULL, APR_HOOK_MIDDLE);
	ap_hook_child_init(xmlBuilderChildInit,NULL,NULL,APR_HOOK_MIDDLE);
}


/* finally, flesh the module */
module AP_MODULE_DECLARE_DATA xmlbuilder_module = {
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	xmlBuilderCreateConfig,
	NULL,
	xmlBuilderCommands,
	xmlBuilderRegisterHooks,
};






/*
char* get_dtd_lang_file(string_array* params, char* default_locale, char* locale_dir) {

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
*/



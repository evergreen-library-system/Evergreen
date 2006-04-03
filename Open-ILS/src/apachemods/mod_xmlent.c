#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "http_request.h"
#include "apr_compat.h"
#include "apr_strings.h"
#include "apr_reslist.h"
#include "http_log.h"
#include "util_filter.h"
#include "opensrf/utils.h"

#include <sys/types.h>
#include <unistd.h>
#include <expat.h>

#define MODULE_NAME	"xmlent_module"

/* Define the config defaults here */
#define MODXMLENT_CONFIG_STRIP_COMMENTS "XMLEntStripComments" 
#define MODXMLENT_CONFIG_CONTENT_TYPE "XMLEntContentType"
#define MODXMLENT_CONFIG_CONTENT_TYPE_DEFAULT "text/html"
#define MODXMLENT_CONFIG_STRIP_PI "XMLEntStripPI"  
#define MODXMLENT_CONFIG_DOCTYPE "XMLEntDoctype"
#define MODXMLENT_CONFIG_STRIP_DOCTYPE "XMLEntStripDoctype"

module AP_MODULE_DECLARE_DATA xmlent_module;

/* our context */
typedef struct {
	apr_bucket_brigade* brigade; /* the bucket brigade we buffer our data into */
	XML_Parser parser; /* our XML parser */
} xmlEntContext;

/* our config data */
typedef struct {
	int stripComments;	/* should we strip comments on the way out? */
	int stripPI;			/* should we strip processing instructions on the way out? */
	int stripDoctype;
	char* contentType;	/* the content type used to server pages */
	char* doctype;			/* the doctype header to send before any other data */
} xmlEntConfig;


/* get the content type from the config */
static const char* xmlEntSetContentType(cmd_parms *params, void *cfg, const char *arg) {
	xmlEntConfig* config = (xmlEntConfig*) cfg;
	config->contentType = (char*) arg;
	return NULL;
}


/* get the stip PI flag from the config */
static const char* xmlEntSetStripPI(cmd_parms *params, void *cfg, const char *arg) {
	xmlEntConfig* config = (xmlEntConfig*) cfg;
	char* a = (char*) arg;
	config->stripPI = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}

/* Get the strip comments flag from the config */
static const char* xmlEntSetStripComments(cmd_parms *params, void *cfg, const char *arg) {
	xmlEntConfig* config = (xmlEntConfig*) cfg;
	char* a = (char*) arg;
	config->stripComments = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}

static const char* xmlEntSetStripDoctype(cmd_parms *params, void *cfg, const char *arg) {
	xmlEntConfig* config = (xmlEntConfig*) cfg;
	char* a = (char*) arg;
	config->stripDoctype = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}


/* Get the user defined doctype from the config */
static const char* xmlEntSetDoctype(cmd_parms *params, void *cfg, const char *arg) {
	xmlEntConfig* config = (xmlEntConfig*) cfg;
	config->doctype = (char*) arg;
	return NULL;
}

/* Tell apache how to set our config variables */
static const command_rec xmlEntCommands[] = {
	AP_INIT_TAKE1( MODXMLENT_CONFIG_STRIP_COMMENTS, 
			xmlEntSetStripComments, NULL, ACCESS_CONF, "XMLENT Strip Comments"),
	AP_INIT_TAKE1( MODXMLENT_CONFIG_CONTENT_TYPE, 
			xmlEntSetContentType, NULL, ACCESS_CONF, "XMLENT Content Type"),
	AP_INIT_TAKE1( MODXMLENT_CONFIG_STRIP_PI,
			xmlEntSetStripPI, NULL, ACCESS_CONF, "XMLENT Strip XML Processing Instructions"),
	AP_INIT_TAKE1( MODXMLENT_CONFIG_DOCTYPE,
			xmlEntSetDoctype, NULL, ACCESS_CONF, "XMLENT Doctype Declaration"),
	AP_INIT_TAKE1( MODXMLENT_CONFIG_STRIP_DOCTYPE,
			xmlEntSetStripDoctype, NULL, ACCESS_CONF, "XMLENT Strip Doctype Declaration"),
	{NULL}
};

/* Creates a new config object */
static void* xmlEntCreateDirConfig( apr_pool_t* p, char* dir ) {
	xmlEntConfig* config = 
		(xmlEntConfig*) apr_palloc( p, sizeof(xmlEntConfig) );

	config->stripComments = 0;
	config->stripPI       = 0;
	config->stripDoctype  = 0;
	config->contentType	 = MODXMLENT_CONFIG_CONTENT_TYPE_DEFAULT;
	config->doctype       = NULL;

	return (void*) config;
}

/* keep for a while in case we ever need it */
/*
#define XMLENT_INHERIT(p, c, f) ((c->f) ? c->f : p->f);
static void* xmlEntMergeDirConfig(apr_pool_t *p, void *base, void *overrides) {
	xmlEntConfig* parent		= base;
	xmlEntConfig* child		= overrides;
	xmlEntConfig* newConf	= (xmlEntConfig*) apr_pcalloc(p, sizeof(xmlEntConfig));
	newConf->contentType = XMLENT_INHERIT(parent, child, contentType);
	newConf->stripComments = XMLENT_INHERIT(parent, child, stripComments);
	return newConf;
}
*/


/* We need a global parser object because sub-requests, with different
 * filter contexts, are parsing part of the same document.
 * This means that this filter will only work in forked (non-threaded) environments.
 * XXX Figure out how to share pointers/data accross filters */
XML_Parser parser = NULL;

/* utility function which passes data to the next filter */
static void _fwrite( ap_filter_t* filter, char* data, ... ) {
	if(!(filter && data)) return;
	xmlEntContext* ctx = (xmlEntContext*) filter->ctx;
	VA_LIST_TO_STRING(data);
	ap_fwrite( filter->next, ctx->brigade, VA_BUF, strlen(VA_BUF));
}


/** XXX move me to  opensrf/utils.h */
#define OSRF_UTILS_REPLACE_CHAR(str, o, n)\
	do {\
		int i = 0;\
		while(str[i] != '\0') {\
			if(str[i] == o)\
				str[i] = n;\
			i++;\
		}\
	} while(0)

/* cycles through the attributes attached to an element */
static void printAttr( ap_filter_t* filter, const char** atts ) {
	if(!atts) return;
	int i;
	for( i = 0; atts[i] && atts[i+1]; i++ ) {
		const char* name = atts[i];
		const char* value = atts[i+1];
		char* escaped = ap_escape_html(filter->r->pool, value); 
		OSRF_UTILS_REPLACE_CHAR(escaped,'\'','"');
		_fwrite( filter, " %s='%s'", name, escaped );
		i++;
	}
}

/* Starts an XML element */
static void XMLCALL startElement(void *userData, const char *name, const char **atts) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	_fwrite(filter, "<%s", name );
	printAttr( filter, atts );
	_fwrite(filter, ">", name );
}

/* Handles the character data */
static void XMLCALL charHandler( void* userData, const XML_Char* s, int len ) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	char data[len+1];
	bzero(data, len+1);
	memcpy( data, s, len );
	char* escaped = ap_escape_html(filter->r->pool, data);
	_fwrite( filter, "%s", escaped );
}

static void XMLCALL handlePI( void* userData, const XML_Char* target, const XML_Char* data) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	_fwrite(filter, "<?%s %s?>", target, data);
}

static void XMLCALL handleComment( void* userData, const XML_Char* comment ) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	_fwrite(filter, "<!-- %s -->", comment);
}

/* Ends an XML element */
static void XMLCALL endElement(void *userData, const char *name) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	_fwrite( filter, "</%s>", name );
}

static void XMLCALL doctypeHandler( void* userData, 
	const char* name, const char* sysid, const char* pubid, int hasinternal ) {

	ap_filter_t* filter = (ap_filter_t*) userData;
	char* s = (sysid) ? (char*) sysid : "";
	char* p = (pubid) ? (char*) pubid : "";
	_fwrite( filter, "<!DOCTYPE %s PUBLIC \"%s\" \"%s\">\n", name, p, s );
}


/* The handler.  Create a new parser and/or filter context where appropriate
 * and parse the chunks of data received from the brigade
 */
static int xmlEntHandler( ap_filter_t *f, apr_bucket_brigade *brigade ) {

	xmlEntContext* ctx = f->ctx;
	apr_bucket* currentBucket = NULL;
	apr_pool_t* pool = f->r->pool;
	const char* data;
  	apr_size_t len;

	/* load the per-dir/location config */
	xmlEntConfig* config = ap_get_module_config( 
			f->r->per_dir_config, &xmlent_module );

	ap_log_rerror(APLOG_MARK, APLOG_DEBUG, 
			0, f->r, "XMLENT Config:\nContent Type = %s, "
			"Strip PI = %s, Strip Comments = %s, Doctype = %s", 
			config->contentType, 
			(config->stripPI) ? "yes" : "no", 
			(config->stripComments) ? "yes" : "no",
			config->doctype);

	/* set the content type based on the config */
	ap_set_content_type(f->r, config->contentType);


	/* create the XML parser */
	int firstrun = 0;
	if( parser == NULL ) {
		firstrun = 1;
		parser = XML_ParserCreate("UTF-8");
		XML_SetUserData(parser, f);
		XML_SetElementHandler(parser, startElement, endElement);
		XML_SetCharacterDataHandler(parser, charHandler);
		if(!config->stripDoctype)
			XML_SetStartDoctypeDeclHandler( parser, doctypeHandler );
		if(!config->stripPI)
			XML_SetProcessingInstructionHandler(parser, handlePI);
		if(!config->stripComments)
			XML_SetCommentHandler(parser, handleComment);
	}

	/* create the filter context */
	if( ctx == NULL ) {
		f->ctx = ctx = apr_pcalloc( pool, sizeof(*ctx));
		ctx->brigade = apr_brigade_create( pool, f->c->bucket_alloc );
		ctx->parser = parser;
	}


	if(firstrun) { /* we haven't started writing the data to the stream yet */

		/* go ahead and write the doctype out if we have one defined */
		if(config->doctype) {
			ap_log_rerror( APLOG_MARK, APLOG_DEBUG, 
					0, f->r, "XMLENT DOCTYPE => %s", config->doctype);
			_fwrite(f, "%s\n", config->doctype);
		}
	}


	/* cycle through the buckets in the brigade */
	while (!APR_BRIGADE_EMPTY(brigade)) {

		/* grab the next bucket */
		currentBucket = APR_BRIGADE_FIRST(brigade);

		/* clean up when we're done */
		if (APR_BUCKET_IS_EOS(currentBucket) || APR_BUCKET_IS_FLUSH(currentBucket)) {
    	  	APR_BUCKET_REMOVE(currentBucket);
      	APR_BRIGADE_INSERT_TAIL(ctx->brigade, currentBucket);
      	ap_pass_brigade(f->next, ctx->brigade);
			XML_ParserFree(parser);
			parser = NULL;
		  	return APR_SUCCESS;
    	}

		/* read the incoming data */
		int s = apr_bucket_read(currentBucket, &data, &len, APR_NONBLOCK_READ);
		if( s != APR_SUCCESS ) {
			ap_log_rerror( APLOG_MARK, APLOG_ERR, 0, f->r, 
					"XMLENT error reading data from filter with status %d", s);
			return s;
		}

		if (len > 0) {

			ap_log_rerror( APLOG_MARK, APLOG_DEBUG, 
					0, f->r, "XMLENT read %d bytes", (int)len);

			/* push data into the XML push parser */
			if ( XML_Parse(ctx->parser, data, len, 0) == XML_STATUS_ERROR ) {

				/* log and die on XML errors */
				ap_log_rerror( APLOG_MARK, APLOG_ERR, 0, f->r, "XMLENT XML Parse Error: %s at line %d\n",
					XML_ErrorString(XML_GetErrorCode(ctx->parser)), 
					XML_GetCurrentLineNumber(ctx->parser));

				XML_ParserFree(parser);
				parser = NULL;
				return HTTP_INTERNAL_SERVER_ERROR; 
			}
    	}

		/* so a subrequest doesn't re-read this bucket */
		apr_bucket_delete(currentBucket); 
  	}

	apr_brigade_destroy(brigade);
  	return APR_SUCCESS;	
}


/* Register the filter function as a filter for modifying the HTTP body (content) */
static void xmlEntRegisterHook(apr_pool_t *pool) {
  ap_register_output_filter("XMLENT", xmlEntHandler, NULL, AP_FTYPE_CONTENT_SET);
}

/* Define the module data */
module AP_MODULE_DECLARE_DATA xmlent_module = {
  STANDARD20_MODULE_STUFF,
  xmlEntCreateDirConfig,	/* dir config creater */
  NULL,							/* dir merger --- default is to override */
  NULL,					      /* server config */
  NULL,                    /* merge server config */
  xmlEntCommands,          /* command apr_table_t */
  xmlEntRegisterHook			/* register hook */
};



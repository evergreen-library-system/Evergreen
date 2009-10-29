#include "httpd.h"
/* vim:noet:ts=4
 */
#include "http_config.h"
#include "http_core.h"
#include "http_protocol.h"
#include "http_request.h"
//#include "apr_compat.h"
#include "apr_strings.h"
#include "apr_reslist.h"
#include "http_log.h"
#include "util_filter.h"
#include "opensrf/string_array.h"
#include "opensrf/utils.h"
#include "opensrf/log.h"

#include <sys/types.h>
#include <unistd.h>
#include <expat.h>

#define APACHE_TOOLS_MAX_POST_SIZE 10485760 /* 10 MB */
#define MODULE_NAME	"idlchunk_module"

/* Define the config defaults here */
#define MODIDLCHUNK_CONFIG_STRIP_COMMENTS "IDLChunkStripComments" 
#define MODIDLCHUNK_CONFIG_CONTENT_TYPE "IDLChunkContentType"
#define MODIDLCHUNK_CONFIG_CONTENT_TYPE_DEFAULT "text/html"
#define MODIDLCHUNK_CONFIG_STRIP_PI "IDLChunkStripPI"  
#define MODIDLCHUNK_CONFIG_DOCTYPE "IDLChunkDoctype"
#define MODIDLCHUNK_CONFIG_STRIP_DOCTYPE "IDLChunkStripDoctype"
#define MODIDLCHUNK_CONFIG_ESCAPE_SCRIPT "IDLChunkEscapeScript"

module AP_MODULE_DECLARE_DATA idlchunk_module;

int idlChunkInScript = 0; /* are we in the middle of a <script> tag */
osrfStringArray* mparams = NULL;

int inChunk = 0;
int all = 0;

/* our context */
typedef struct {
	apr_bucket_brigade* brigade; /* the bucket brigade we buffer our data into */
	XML_Parser parser; /* our XML parser */
} idlChunkContext;

/* our config data */
typedef struct {
	int stripComments;	/* should we strip comments on the way out? */
	int stripPI;			/* should we strip processing instructions on the way out? */
	int stripDoctype;
	int escapeScript;		/* if true, we html-escape anything text inside a <script> tag */
	char* contentType;	/* the content type used to server pages */
	char* doctype;			/* the doctype header to send before any other data */
} idlChunkConfig;


static osrfStringArray* apacheParseParms(request_rec* r) {

	if( r == NULL ) return NULL;
	//ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r, "got a valid request_rec");

	char* arg = NULL;
	apr_pool_t *p = r->pool;	/* memory pool */
	growing_buffer* buffer = buffer_init(1025);

	/* gather the post args and append them to the url query string */
	if( !strcmp(r->method,"POST") ) {

		ap_setup_client_block(r, REQUEST_CHUNKED_DECHUNK);
		
		//osrfLogDebug(OSRF_LOG_MARK, "gateway reading post data..");
	    //ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r, "idlchunk reading post data..");

		if(ap_should_client_block(r)) {


			/* Start with url query string, if any */
			
			if(r->args && r->args[0])
				buffer_add(buffer, r->args);

			char body[1025];

			//osrfLogDebug(OSRF_LOG_MARK, "gateway client has post data, reading...");

			/* Append POST data */
			
			long bread;
			while( (bread = ap_get_client_block(r, body, sizeof(body) - 1)) ) {

				if(bread < 0) {
					//osrfLogInfo(OSRF_LOG_MARK, 
					//	"ap_get_client_block(): returned error, exiting POST reader");
					break;
				}

				body[bread] = '\0';
				buffer_add( buffer, body );

				//osrfLogDebug(OSRF_LOG_MARK, 
				//	"gateway read %ld bytes: %d bytes of data so far", bread, buffer->n_used);

				if(buffer->n_used > APACHE_TOOLS_MAX_POST_SIZE) {
					//osrfLogError(OSRF_LOG_MARK, "gateway received POST larger "
					//	"than %d bytes. dropping request", APACHE_TOOLS_MAX_POST_SIZE);
					buffer_free(buffer);
					return NULL;
				}
			}

			//osrfLogDebug(OSRF_LOG_MARK, "gateway done reading post data");
		}

	} else { /* GET */

        if(r->args && r->args[0])
            buffer_add(buffer, r->args);
	    //ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r, "idlchunk read GET data..");
    }


    if(buffer->n_used > 0)
        arg = apr_pstrdup(p, buffer->buf);
    else
        arg = NULL; 
    buffer_free(buffer);

	if( !arg || !arg[0] ) { /* we received no request */
		return NULL;
	}

	//osrfLogDebug(OSRF_LOG_MARK, "parsing URL params from post/get request data: %s", arg);
	//ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r, "parsing URL params from post/get request data: %s", arg);
	
	osrfStringArray* sarray		= osrfNewStringArray(12); /* method parameters */
	int sanity = 0;
	char* key					= NULL;	/* query item name */
	char* val					= NULL;	/* query item value */

	/* Parse the post/get request data into a series of name/value pairs.   */
	/* Load each name into an even-numbered slot of an osrfStringArray, and */
	/* the corresponding value into the following odd-numbered slot.        */

	while( arg && (val = ap_getword(p, (const char**) &arg, '&'))) {

		key = ap_getword(r->pool, (const char**) &val, '=');
		if(!key || !key[0])
			break;

		ap_unescape_url(key);
		ap_unescape_url(val);

		//osrfLogDebug(OSRF_LOG_MARK, "parsed URL params %s=%s", key, val);

		osrfStringArrayAdd(sarray, key);
		osrfStringArrayAdd(sarray, val);

		if( sanity++ > 1000 ) {
			//osrfLogError(OSRF_LOG_MARK, 
			//	"Parsing URL params failed sanity check: 1000 iterations");
			osrfStringArrayFree(sarray);
			return NULL;
		}

	}

	//osrfLogDebug(OSRF_LOG_MARK,
	//	"Apache tools parsed %d params key/values", sarray->size / 2 );

	return sarray;
}



static osrfStringArray* apacheGetParamKeys(osrfStringArray* params) {
	if(params == NULL) return NULL;	
	osrfStringArray* sarray = osrfNewStringArray(12);
	int i;
	//osrfLogDebug(OSRF_LOG_MARK, "Fetching URL param keys");
	for( i = 0; i < params->size; i++ ) 
		osrfStringArrayAdd(sarray, osrfStringArrayGetString(params, i++));
	return sarray;
}

static osrfStringArray* apacheGetParamValues(osrfStringArray* params, char* key) {

	if(params == NULL || key == NULL) return NULL;	
	osrfStringArray* sarray	= osrfNewStringArray(12);

	//osrfLogDebug(OSRF_LOG_MARK, "Fetching URL values for key %s", key);
	int i;
	for( i = 0; i < params->size; i++ ) {
		const char* nkey = osrfStringArrayGetString(params, i++);
		if(nkey && !strcmp(nkey, key)) 
			osrfStringArrayAdd(sarray, osrfStringArrayGetString(params, i));
	}
	return sarray;
}


static char* apacheGetFirstParamValue(osrfStringArray* params, char* key) {
	if(params == NULL || key == NULL) return NULL;	

	int i;
	//osrfLogDebug(OSRF_LOG_MARK, "Fetching first URL value for key %s", key);
	for( i = 0; i < params->size; i++ ) {
		const char* nkey = osrfStringArrayGetString(params, i++);
		if(nkey && !strcmp(nkey, key)) 
			return strdup(osrfStringArrayGetString(params, i));
	}

	return NULL;
}


static int apacheDebug( char* msg, ... ) {
	VA_LIST_TO_STRING(msg);
	fprintf(stderr, "%s\n", VA_BUF);
	fflush(stderr);
	return 0;
}


static int apacheError( char* msg, ... ) {
	VA_LIST_TO_STRING(msg);
	fprintf(stderr, "%s\n", VA_BUF);
	fflush(stderr);
	return HTTP_INTERNAL_SERVER_ERROR; 
}




/* get the content type from the config */
static const char* idlChunkSetContentType(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	config->contentType = (char*) arg;
	return NULL;
}


/* get the strip PI flag from the config */
static const char* idlChunkSetStripPI(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	char* a = (char*) arg;
	config->stripPI = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}

/* Get the strip comments flag from the config */
static const char* idlChunkSetStripComments(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	char* a = (char*) arg;
	config->stripComments = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}

static const char* idlChunkSetEscapeScript(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	char* a = (char*) arg;
	config->escapeScript = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}

static const char* idlChunkSetStripDoctype(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	char* a = (char*) arg;
	config->stripDoctype = (a && !strcasecmp(a, "yes")) ? 1 : 0;
	return NULL;
}


/* Get the user defined doctype from the config */
static const char* idlChunkSetDoctype(cmd_parms *params, void *cfg, const char *arg) {
	idlChunkConfig* config = (idlChunkConfig*) cfg;
	config->doctype = (char*) arg;
	return NULL;
}

/* Tell apache how to set our config variables */
static const command_rec idlChunkCommands[] = {
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_STRIP_COMMENTS, 
			idlChunkSetStripComments, NULL, ACCESS_CONF, "IDLCHUNK Strip Comments"),
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_CONTENT_TYPE, 
			idlChunkSetContentType, NULL, ACCESS_CONF, "IDLCHUNK Content Type"),
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_STRIP_PI,
			idlChunkSetStripPI, NULL, ACCESS_CONF, "IDLCHUNK Strip XML Processing Instructions"),
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_DOCTYPE,
			idlChunkSetDoctype, NULL, ACCESS_CONF, "IDLCHUNK Doctype Declaration"),
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_STRIP_DOCTYPE,
			idlChunkSetStripDoctype, NULL, ACCESS_CONF, "IDLCHUNK Strip Doctype Declaration"),
	AP_INIT_TAKE1( MODIDLCHUNK_CONFIG_ESCAPE_SCRIPT,
			idlChunkSetEscapeScript, NULL, ACCESS_CONF, "IDLCHUNK Escape data in script tags"),
	{NULL}
};

/* Creates a new config object */
static void* idlChunkCreateDirConfig( apr_pool_t* p, char* dir ) {
	idlChunkConfig* config = 
		(idlChunkConfig*) apr_palloc( p, sizeof(idlChunkConfig) );

	config->stripComments = 0;
	config->stripPI       = 0;
	config->stripDoctype  = 1;
	config->escapeScript	 = 1;
	config->contentType	 = MODIDLCHUNK_CONFIG_CONTENT_TYPE_DEFAULT;
	config->doctype       = NULL;

	return (void*) config;
}

/* keep for a while in case we ever need it */
/*
#define IDLCHUNK_INHERIT(p, c, f) ((c->f) ? c->f : p->f);
static void* idlChunkMergeDirConfig(apr_pool_t *p, void *base, void *overrides) {
	idlChunkConfig* parent		= base;
	idlChunkConfig* child		= overrides;
	idlChunkConfig* newConf	= (idlChunkConfig*) apr_pcalloc(p, sizeof(idlChunkConfig));
	newConf->contentType = IDLCHUNK_INHERIT(parent, child, contentType);
	newConf->stripComments = IDLCHUNK_INHERIT(parent, child, stripComments);
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
	idlChunkContext* ctx = (idlChunkContext*) filter->ctx;
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
static char* find_id_attr( const char** atts ) {
	if(!atts) return NULL;
	int i;
	for( i = 0; atts[i] && atts[i+1]; i++ ) {
		const char* name = atts[i];
		char* value = (char*)atts[i+1];
        if (!strcmp(name,"id")) return value;
		i++;
	}
}

/* cycles through the attributes attached to an element */
static void printAttr( ap_filter_t* filter, const char** atts ) {
	if(!atts) return;
	int i;
	for( i = 0; atts[i] && atts[i+1]; i++ ) {
		const char* name = atts[i];
		const char* value = atts[i+1];
		char* escaped = ap_escape_html(filter->r->pool, value); 

		/* we make a big assumption here that if the string contains a ', 
		 * then the original attribute was wrapped in "s - so recreate that */
		if( strchr( escaped, '\'' ) ) {
			OSRF_UTILS_REPLACE_CHAR(escaped,'"','\'');
			_fwrite( filter, " %s=\"%s\"", name, escaped );

		} else {
			OSRF_UTILS_REPLACE_CHAR(escaped,'\'','"');
			_fwrite( filter, " %s='%s'", name, escaped );
		}

		i++;
	}
}

/* Starts an XML element */
static void XMLCALL startElement(void *userData, const char *name, const char **atts) {

    ap_filter_t* filter = (ap_filter_t*) userData;


    if (!strcmp(name,"class")) {
        //ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, filter->r,"Looking at %s with id of %s",name, find_id_attr(atts));

        if (osrfStringArrayContains(mparams, find_id_attr(atts))) {
            inChunk = 1;
	        //ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, filter->r,"Found desired class %s", find_id_attr(atts));
        }
    }

    if (all || inChunk || (name && (!strcmp(name,"IDL")))) {

	    idlChunkConfig* config = ap_get_module_config( 
		    	filter->r->per_dir_config, &idlchunk_module );
    	_fwrite(filter, "<%s", name );
	    printAttr( filter, atts );
    	if (!strncmp(config->contentType, MODIDLCHUNK_CONFIG_CONTENT_TYPE_DEFAULT, 9)) {
	    	_fwrite(filter, " />", name );
    	} else {
	    	_fwrite(filter, ">", name );
    	}
	    if(!strcmp(name, "script")) 
    		idlChunkInScript = 1;
    }
}

/* Handles the character data */
static void XMLCALL charHandler( void* userData, const XML_Char* s, int len ) {
	ap_filter_t* filter = (ap_filter_t*) userData;
	char data[len+1];
	memset( data, '\0', sizeof(data) );
	memcpy( data, s, len );

	idlChunkConfig* config = ap_get_module_config( 
			filter->r->per_dir_config, &idlchunk_module );

    if (all || inChunk) {
    	if( idlChunkInScript && ! config->escapeScript ) {
	    	_fwrite( filter, "%s", data );

    	} else {
	    	char* escaped = ap_escape_html(filter->r->pool, data);
    		_fwrite( filter, "%s", escaped );
	    } 
    }
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

    if (all || inChunk || (name && (!strcmp(name,"IDL")))) {

    	ap_filter_t* filter = (ap_filter_t*) userData;
    	idlChunkConfig* config = ap_get_module_config( 
    			filter->r->per_dir_config, &idlchunk_module );
    	if (!strncmp(config->contentType, MODIDLCHUNK_CONFIG_CONTENT_TYPE_DEFAULT, 9)) { 
    		return;
    	}
    	_fwrite( filter, "</%s>", name );
    	if(!strcmp(name, "script")) 
    		idlChunkInScript = 1;
    
    }
    if (!strcmp(name,"class")) inChunk = 0;
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
static int idlChunkHandler( ap_filter_t *f, apr_bucket_brigade *brigade ) {

	idlChunkContext* ctx = f->ctx;
	apr_bucket* currentBucket = NULL;
	apr_pool_t* pool = f->r->pool;
	const char* data;
  	apr_size_t len;
    osrfStringArray* params = NULL;
    mparams = NULL;

	/* load the per-dir/location config */
	idlChunkConfig* config = ap_get_module_config( 
			f->r->per_dir_config, &idlchunk_module );

	ap_log_rerror(APLOG_MARK, APLOG_ERR, 
			0, f->r, "IDLCHUNK Config:\nContent Type = %s, "
			"Strip PI = %s, Strip Comments = %s, Doctype = %s", 
			config->contentType, 
			(config->stripPI) ? "yes" : "no", 
			(config->stripComments) ? "yes" : "no",
			config->doctype);

	/* set the content type based on the config */
	ap_set_content_type(f->r, config->contentType);

	//ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, f->r, "Set content type");

    params = apacheParseParms(f->r); /* free me */
    mparams = apacheGetParamValues( params, "class" ); /* free me */

    all = 1;

    if (mparams && mparams->size > 0) all = 0;

	//ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, f->r, "Parsed the params, if any");

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
					0, f->r, "IDLCHUNK DOCTYPE => %s", config->doctype);
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
            if (params) osrfStringArrayFree(params);
            if (mparams) osrfStringArrayFree(mparams);
			parser = NULL;
		  	return APR_SUCCESS;
    	}

		/* read the incoming data */
		int s = apr_bucket_read(currentBucket, &data, &len, APR_NONBLOCK_READ);
		if( s != APR_SUCCESS ) {
			ap_log_rerror( APLOG_MARK, APLOG_ERR, 0, f->r, 
					"IDLCHUNK error reading data from filter with status %d", s);
            if (params) osrfStringArrayFree(params);
            if (mparams) osrfStringArrayFree(mparams);
			return s;
		}

		if (len > 0) {

			ap_log_rerror( APLOG_MARK, APLOG_DEBUG, 
					0, f->r, "IDLCHUNK read %d bytes", (int)len);

			/* push data into the XML push parser */
			if ( XML_Parse(ctx->parser, data, len, 0) == XML_STATUS_ERROR ) {

                char tmp[len+1];
                memcpy(tmp, data, len);
                tmp[len] = '\0';

				/* log and die on XML errors */
				ap_log_rerror( APLOG_MARK, APLOG_ERR, 0, f->r, 
                    "IDLCHUNK XML Parse Error: %s at line %d: parsing %s: data %s",
					XML_ErrorString(XML_GetErrorCode(ctx->parser)), 
					(int) XML_GetCurrentLineNumber(ctx->parser), f->r->filename, tmp);

				XML_ParserFree(parser);
                if (params) osrfStringArrayFree(params);
                if (mparams) osrfStringArrayFree(mparams);
				parser = NULL;
				return HTTP_INTERNAL_SERVER_ERROR; 
			}
    	}

		/* so a subrequest doesn't re-read this bucket */
		apr_bucket_delete(currentBucket); 
  	}

	apr_brigade_destroy(brigade);
    if (params) osrfStringArrayFree(params);
    if (mparams) osrfStringArrayFree(mparams);
  	return APR_SUCCESS;	
}


/* Register the filter function as a filter for modifying the HTTP body (content) */
static void idlChunkRegisterHook(apr_pool_t *pool) {
  ap_register_output_filter("IDLCHUNK", idlChunkHandler, NULL, AP_FTYPE_CONTENT_SET);
}

/* Define the module data */
module AP_MODULE_DECLARE_DATA idlchunk_module = {
  STANDARD20_MODULE_STUFF,
  idlChunkCreateDirConfig,	/* dir config creater */
  NULL,							/* dir merger --- default is to override */
  NULL,					      /* server config */
  NULL,                    /* merge server config */
  idlChunkCommands,          /* command apr_table_t */
  idlChunkRegisterHook			/* register hook */
};





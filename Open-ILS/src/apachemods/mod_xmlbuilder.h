#include "apachetools.h"
#include "opensrf/xml_utils.h"
#include "opensrf/osrf_hash.h"
#include "opensrf/osrf_list.h"
#include <libxslt/xslt.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>

#define MODULE_NAME	"xmlbuilder_module" 	/* our module name */

/* ------------------------------------------------------------------------------ */
/* Apache config items.  These are defaults which are only  used if they are not
	overriden by the Apache config or URL where appropriate */
/* ------------------------------------------------------------------------------ */
/* The default directory where the DTD files are stored */
#define MODXMLB_DEFAULT_LOCALE_PARAM	"locale"
#define MODXMLB_DEFAULT_BASE_DIR			"/openils/var/web/locale"
#define MODXMLB_DEFAULT_LOCALE			"en-US"			
#define MODXMLB_DEFAULT_DTD				NULL /* if defined, use this DTD only */
/* ------------------------------------------------------------------------------ */

#define MODXMLB_CONFIG_LOCALE 		"XMLBuilderDefaultLocale"
#define MODXMLB_CONFIG_BASE_DIR		"XMLBuilderBaseDir"
#define MODXMLB_CONFIG_POST_XSL 		"XMLBuilderPostXSL"
#define MODXMLB_CONFIG_DEFAULT_DTD	"XMLBuilderDefaultDTD"
#define MODXMLB_CONFIG_LOCALE_PARAM "XMLBuilderLocaleParam"



/* This module */
module AP_MODULE_DECLARE_DATA xmlbuilder_module;


/* our config structure */
typedef struct {

	char* baseDir;					/* directory on disk where the DTD files live */
	char* defaultLocale;			/* locale dir from config or default */
	char* defaultDtd;				/* if defined, we load this DTD only */
	char* localeParam;			/* the CGI param used to choose the locale dir dynamically */
	xsltStylesheetPtr postXSL;	/* if defined, run this XSL after parsing */

} xmlBuilderConfig;

typedef struct {
	xmlBuilderConfig* config;
	xmlDocPtr doc;
	osrfHash* entHash;
	osrfHash* dtdHash;
	osrfList* nodeList;
	int xmlError;
	char* xmlFile;
} xmlBuilderContext;



xmlDocPtr xmlBuilderProcessFile( char* XMLFile, xmlBuilderConfig* config );

void xmlBuilderAddDtd( const char* sysId, xmlBuilderContext* context );


/* SAX Callbacks */
void xmlBuilderStartElement( void* blob, const xmlChar *name, const xmlChar **atts );
void xmlBuilderEndElement( void* blob, const xmlChar* name );
void xmlBuilderHandleCharacter(void* blob, const xmlChar *ch, int len);
void xmlBuilderParseError( void* blob, const char* msg, ... );
xmlEntityPtr xmlBuilderGetEntity( void* blob, const xmlChar* name );
void xmlBuilderExtSubset( void* blob, const xmlChar* name, const xmlChar* extId, const xmlChar* sysId );
void xmlBuilderProcInstruction( void* blob, const xmlChar* name, const xmlChar* data );

static xmlSAXHandler xmlBuilderSaxHandlerStruct = {
   NULL,								/* internalSubset */
   NULL,								/* isStandalone */
   NULL,								/* hasInternalSubset */
   NULL,								/* hasExternalSubset */
   NULL,								/* resolveEntity */
   xmlBuilderGetEntity,			/* getEntity */
   NULL, 							/* entityDecl */
   NULL,								/* notationDecl */
   NULL,								/* attributeDecl */
   NULL,								/* elementDecl */
   NULL, 							/* unparsedEntityDecl */
   NULL,								/* setDocumentLocator */
   NULL,								/* startDocument */
   NULL,								/* endDocument */
	xmlBuilderStartElement,		/* startElement */
	xmlBuilderEndElement,		/* endElement */
   NULL,								/* reference */
	xmlBuilderHandleCharacter,	/* characters */
   NULL,								/* ignorableWhitespace */
   xmlBuilderProcInstruction, /* processingInstruction */
   NULL,								/* comment */
   xmlBuilderParseError,		/* xmlParserWarning */
   xmlBuilderParseError,		/* xmlParserError */
   NULL,								/* xmlParserFatalError : unused */
   NULL,								/* getParameterEntity */
   NULL,								/* cdataBlock; */
   xmlBuilderExtSubset,			/* externalSubset; */
   1,
   NULL,
   NULL,								/* startElementNs */
   NULL,								/* endElementNs */
	NULL								/* xmlStructuredErrorFunc */
};
static const xmlSAXHandlerPtr xmlBuilderSaxHandler = &xmlBuilderSaxHandlerStruct;



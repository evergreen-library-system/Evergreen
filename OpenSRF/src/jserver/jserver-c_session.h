#define _GNU_SOURCE

#include "opensrf/utils.h"
#include "opensrf/logging.h"

#include "jstrings.h"

#include <stdio.h>
#include <string.h>

#include <libxml/globals.h>
#include <libxml/xmlerror.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h> /* only for xmlNewInputFromFile() */
#include <libxml/tree.h>
#include <libxml/debugXML.h>
#include <libxml/xmlmemory.h>


/* session states */
#define JABBER_STATE_CONNECTED			2
#define JABBER_STATE_CONNECTING			4 
#define JABBER_STATE_IN_MESSAGE			8	


struct jserver_session_struct {

	/* our connection state */
	unsigned int state;

	/* incoming XML is parsed with the SAX parser */
	xmlParserCtxtPtr parser_ctxt;

	/* incoming message are shoved into this DOM doc after they are parsed */
	xmlDocPtr current_msg;

	/* we have to grab off the from and to for routing */
	char* current_to;
	char* current_from;

	char* current_domain;
	char* current_resource;
	char* current_username;

	int in_iq;
	int in_uname;
	int in_resource;

	void* blob; /* callback blob - can be anything that needs passing around */
	void (*on_msg_complete) (void* blob, char* msg_xml, char* from, char* to );

	/* happens after someone logs in and we've pieced together the from address */
	void (*on_from_discovered) (void* blob, char* from );
	void (*on_login_init) (void* blob, char* reply );
	void (*on_login_ok) (void* blob);
	void (*on_client_finish) (void* blob);

};
typedef struct jserver_session_struct jserver_session;


jserver_session* jserver_session_init();
void jserver_session_free(jserver_session* session);
char* sax_xml_attr( const xmlChar** atts, char* attr_name );
int jserver_session_push_data(jserver_session* session, char* data);

void dom_add_attrs(xmlNodePtr node, const xmlChar** atts);
char* _xml_to_string( xmlDocPtr doc ); 


// ---------------------------------------------------------------------------------
// Our SAX handlers 
// ---------------------------------------------------------------------------------
void sax_start_element( 
		void *session, const xmlChar *name, const xmlChar **atts);

void sax_end_element( void* blob, const xmlChar *name);

void sax_start_doc(void* blob);
//void sax_end_doc(void* blob);

void sax_character( void* blob, const xmlChar *ch, int len);

void  sax_warning( void* blob, const char* msg, ... );

static xmlSAXHandler sax_handler_struct = {
   NULL,						/* internalSubset */
   NULL,						/* isStandalone */
   NULL,						/* hasInternalSubset */
   NULL,						/* hasExternalSubset */
   NULL,						/* resolveEntity */
   NULL,						/* getEntity */
   NULL,						/* entityDecl */
   NULL,						/* notationDecl */
   NULL,						/* attributeDecl */
   NULL,						/* elementDecl */
   NULL,						/* unparsedEntityDecl */
   NULL,						/* setDocumentLocator */
   sax_start_doc,			/* startDocument */
   NULL,						/* endDocument */
	sax_start_element,	/* startElement */
	sax_end_element,		/* endElement */
   NULL,						/* reference */
	sax_character,			/* characters */
   NULL,						/* ignorableWhitespace */
   NULL,						/* processingInstruction */
   NULL,						/* comment */
   sax_warning,			/* xmlParserWarning */
   sax_warning,			/* xmlParserError */
   NULL,						/* xmlParserFatalError : unused */
   NULL,						/* getParameterEntity */
   NULL,						/* cdataBlock; */
   NULL,						/* externalSubset; */
   1,
   NULL,
   NULL,						/* startElementNs */
   NULL,						/* endElementNs */
	NULL						/* xmlStructuredErrorFunc */
};

static const xmlSAXHandlerPtr sax_handler = &sax_handler_struct;

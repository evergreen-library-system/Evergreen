#include "opensrf/string_array.h"
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "objson/object.h"
#include "objson/json_parser.h"


/* libxml stuff for the config reader */
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/tree.h>



#ifndef osrf_message_h
#define osrf_message_h

#define OSRF_XML_NAMESPACE "http://open-ils.org/xml/namespaces/oils_v1"

#define OSRF_STATUS_CONTINUE						100

#define OSRF_STATUS_OK								200
#define OSRF_STATUS_ACCEPTED						202
#define OSRF_STATUS_COMPLETE						205

#define OSRF_STATUS_REDIRECTED					307

#define OSRF_STATUS_BADREQUEST					400
#define OSRF_STATUS_UNAUTHORIZED					401
#define OSRF_STATUS_FORBIDDEN						403
#define OSRF_STATUS_NOTFOUND						404
#define OSRF_STATUS_NOTALLOWED					405
#define OSRF_STATUS_TIMEOUT						408
#define OSRF_STATUS_EXPFAILED						417

#define OSRF_STATUS_INTERNALSERVERERROR		500
#define OSRF_STATUS_NOTIMPLEMENTED				501
#define OSRF_STATUS_VERSIONNOTSUPPORTED		505


enum M_TYPE { CONNECT, REQUEST, RESULT, STATUS, DISCONNECT };

#define OSRF_MAX_PARAMS								128;

struct osrf_message_struct {

	enum M_TYPE m_type;
	int thread_trace;
	int protocol;

	/* if we're a STATUS message */
	char* status_name;

	/* if we're a STATUS or RESULT */
	char* status_text;
	int status_code;

	int is_exception;

	/* if we're a RESULT */
	jsonObject* _result_content;

	/* unparsed json string */
	char* result_string;

	/* if we're a REQUEST */
	char* method_name;

	jsonObject* _params;

	/* in case anyone wants to make a list of us.  
		we won't touch this variable */
	struct osrf_message_struct* next;

	char* full_param_string;

};
typedef struct osrf_message_struct osrf_message;
typedef struct osrf_message_struct osrfMessage;


osrf_message* osrf_message_init( enum M_TYPE type, int thread_trace, int protocol );
//void osrf_message_set_request_info( osrf_message*, char* param_name, json* params );
void osrf_message_set_status_info( osrf_message*, char* status_name, char* status_text, int status_code );
void osrf_message_set_result_content( osrf_message*, char* json_string );
void osrfMessageFree( osrfMessage* );
void osrf_message_free( osrf_message* );
char* osrf_message_to_xml( osrf_message* );
char* osrf_message_serialize(osrf_message*);

/* count is the max number of messages we'll put into msgs[] */
int osrf_message_deserialize(char* json, osrf_message* msgs[], int count);



/** Pushes any message retreived from the xml into the 'msgs' array.
  * it is assumed that 'msgs' has beenn pre-allocated.
  * Returns the number of message that are in the buffer.
  */
int osrf_message_from_xml( char* xml, osrf_message* msgs[] );

void osrf_message_set_params( osrf_message* msg, jsonObject* o );
void osrf_message_set_method( osrf_message* msg, char* method_name );
void osrf_message_add_object_param( osrf_message* msg, jsonObject* o );
void osrf_message_add_param( osrf_message*, char* param_string );


jsonObject* osrfMessageGetResult( osrfMessage* msg );

/**
  Returns the message as a jsonObject
  @return The jsonObject which must be freed by the caller.
  */
jsonObject* osrfMessageToJSON( osrfMessage* msg );

char* osrfMessageSerializeBatch( osrfMessage* msgs [], int count );


#endif

#include "libjson/json.h"
#include "opensrf/generic_utils.h"

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
	json* result_content;

	/* if we're a REQUEST */
	char* method_name;
	json* params;

	/* in case anyone wants to make a list of us.  
		we won't touch this variable */
	struct osrf_message_struct* next;

};
typedef struct osrf_message_struct osrf_message;


osrf_message* osrf_message_init( enum M_TYPE type, int thread_trace, int protocol );
void osrf_message_set_request_info( osrf_message*, char* param_name, json* params );
void osrf_message_set_status_info( osrf_message*, char* status_name, char* status_text, int status_code );
void osrf_message_set_result_content( osrf_message*, json* result_content );
void osrf_message_free( osrf_message* );
char* osrf_message_to_xml( osrf_message* );
/** Pushes any message retreived from the xml into the 'msgs' array.
  * it is assumed that 'msgs' has beenn pre-allocated.
  * Returns the number of message that are in the buffer.
  */
int osrf_message_from_xml( char* xml, osrf_message* msgs[] );




#endif

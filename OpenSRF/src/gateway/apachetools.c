#include "apachetools.h"

string_array* apacheParseParms(request_rec* r) {

	if( r == NULL ) return NULL;

	char* arg = r->args;			/* url query string */
	apr_pool_t *p = r->pool;	/* memory pool */
	string_array* sarray			= init_string_array(12); /* method parameters */

	growing_buffer* buffer		= NULL;	/* POST data */
	growing_buffer* tmp_buf		= NULL;	/* temp buffer */

	char* key						= NULL;	/* query item name */
	char* val						= NULL;	/* query item value */

	/* gather the post args and append them to the url query string */
	if( !strcmp(r->method,"POST") ) {

		ap_setup_client_block(r, REQUEST_CHUNKED_DECHUNK);
		
		osrfLogDebug(OSRF_LOG_MARK, "gateway reading post data..");

		if(ap_should_client_block(r)) {

			char body[1025];
			memset(body,0,1025);
			buffer = buffer_init(1025);


			osrfLogDebug(OSRF_LOG_MARK, "gateway client has post data, reading...");
	
			long bread;
			while( (bread = ap_get_client_block(r, body, 1024)) ) {

				if(bread < 0) {
					osrfLogInfo(OSRF_LOG_MARK, 
						"ap_get_client_block(): returned error, exiting POST reader");
					break;
				}

				buffer_add( buffer, body );
				memset(body,0,1025);

				osrfLogDebug(OSRF_LOG_MARK, 
					"gateway read %d bytes: %d bytes of data so far", bread, buffer->n_used);

				if(buffer->n_used == 0) break;

				if(buffer->n_used > APACHE_TOOLS_MAX_POST_SIZE) {
					osrfLogError(OSRF_LOG_MARK, "gateway received POST larger "
						"than %d bytes. dropping reqeust", APACHE_TOOLS_MAX_POST_SIZE);
					buffer_free(buffer);
					return NULL;
				}
			}

			osrfLogDebug(OSRF_LOG_MARK, "gateway done reading post data");
	
			if(arg && arg[0]) {

				tmp_buf = buffer_init(1024);
				buffer_add(tmp_buf,arg);
				buffer_add(tmp_buf,buffer->buf);
				arg = (char*) apr_pstrdup(p, tmp_buf->buf);
				buffer_free(tmp_buf);

			} else if(buffer->n_used > 0){
					arg = (char*) apr_pstrdup(p, buffer->buf);

			} else { 
				arg = NULL; 
			}

			buffer_free(buffer);
		}
	} 


	osrfLogDebug(OSRF_LOG_MARK, "gateway done mangling post data");

	if( !arg || !arg[0] ) { /* we received no request */
		return NULL;
	}


	osrfLogDebug(OSRF_LOG_MARK, "parsing URL params from post/get request data: %s", arg);
	int sanity = 0;
	while( arg && (val = ap_getword(p, (const char**) &arg, '&'))) {

		key = ap_getword(r->pool, (const char**) &val, '=');
		if(!key || !key[0])
			break;

		ap_unescape_url((char*)key);
		ap_unescape_url((char*)val);

		osrfLogDebug(OSRF_LOG_MARK, "parsed URL params %s=%s", key, val);

		string_array_add(sarray, key);
		string_array_add(sarray, val);

		if( sanity++ > 1000 ) {
			osrfLogError(OSRF_LOG_MARK, 
				"Parsing URL params failed sanity check: 1000 iterations");
			string_array_destroy(sarray);
			return NULL;
		}

	}

	if(sarray)
		osrfLogDebug(OSRF_LOG_MARK, 
			"Apache tools parsed %d params key/values", sarray->size / 2 );

	return sarray;
}



string_array* apacheGetParamKeys(string_array* params) {
	if(params == NULL) return NULL;	
	string_array* sarray	= init_string_array(12); 
	int i;
	osrfLogDebug(OSRF_LOG_MARK, "Fetching URL param keys");
	for( i = 0; i < params->size; i++ ) 
		string_array_add(sarray, string_array_get_string(params, i++));	
	return sarray;
}

string_array* apacheGetParamValues(string_array* params, char* key) {

	if(params == NULL || key == NULL) return NULL;	
	string_array* sarray	= init_string_array(12); 

	osrfLogDebug(OSRF_LOG_MARK, "Fetching URL values for key %s", key);
	int i;
	for( i = 0; i < params->size; i++ ) {
		char* nkey = string_array_get_string(params, i++);	
		if(key && !strcmp(nkey, key)) 
			string_array_add(sarray, string_array_get_string(params, i));	
	}
	return sarray;
}


char* apacheGetFirstParamValue(string_array* params, char* key) {
	if(params == NULL || key == NULL) return NULL;	

	int i;
	osrfLogDebug(OSRF_LOG_MARK, "Fetching first URL value for key %s", key);
	for( i = 0; i < params->size; i++ ) {
		char* nkey = string_array_get_string(params, i++);	
		if(key && !strcmp(nkey, key)) 
			return strdup(string_array_get_string(params, i));
	}

	return NULL;
}


int apacheDebug( char* msg, ... ) {
	VA_LIST_TO_STRING(msg);
	fprintf(stderr, "%s\n", VA_BUF);
	fflush(stderr);
	return 0;
}


int apacheError( char* msg, ... ) {
	VA_LIST_TO_STRING(msg);
	fprintf(stderr, "%s\n", VA_BUF);
	fflush(stderr);
	return HTTP_INTERNAL_SERVER_ERROR; 
}



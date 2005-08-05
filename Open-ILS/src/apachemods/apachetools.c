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

		if(ap_should_client_block(r)) {

			char body[1025];
			memset(body,0,1025);
			buffer = buffer_init(1025);
	
			while(ap_get_client_block(r, body, 1024)) {
				buffer_add( buffer, body );
				memset(body,0,1025);
			}
	
			if(arg && arg[0]) {

				tmp_buf = buffer_init(1024);
				buffer_add(tmp_buf,arg);
				buffer_add(tmp_buf,buffer->buf);
				arg = (char*) apr_pstrdup(p, tmp_buf->buf);
				buffer_free(tmp_buf);

			} else {
				arg = (char*) apr_pstrdup(p, buffer->buf);
			}

			buffer_free(buffer);
		}
	} 


	if( ! arg || !arg[0] ) { /* we received no request */
		return NULL;
	}


	while( arg && (val = ap_getword(p, (const char**) &arg, '&'))) {

		key = ap_getword(r->pool, (const char**) &val, '=');
		if(!key || !key[0])
			break;

		ap_unescape_url((char*)key);
		ap_unescape_url((char*)val);

		string_array_add(sarray, key);
		string_array_add(sarray, val);

	}

	return sarray;

}



string_array* apacheGetParamKeys(string_array* params) {
	if(params == NULL) return NULL;	
	string_array* sarray	= init_string_array(12); 
	int i;
	for( i = 0; i < params->size; i++ ) 
		string_array_add(sarray, string_array_get_string(params, i++));	
	return sarray;
}

string_array* apacheGetParamValues(string_array* params, char* key) {

	if(params == NULL || key == NULL) return NULL;	
	string_array* sarray	= init_string_array(12); 

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
	for( i = 0; i < params->size; i++ ) {
		char* nkey = string_array_get_string(params, i++);	
		if(key && !strcmp(nkey, key)) 
			return strdup(string_array_get_string(params, i));
	}

	return NULL;
}

	

#include "osrf_config.h"

void config_reader_init( char* name, char* config_file ) {

	if( name == NULL || config_file == NULL || strlen(config_file) == 0 ) {
		fatal_handler( "config_reader_init(): No config file specified" );
		return;
	}

	config_reader* reader = 
		(config_reader*) safe_malloc(sizeof(config_reader));

	reader->config_doc = xmlParseFile( config_file ); 
	reader->xpathCx = xmlXPathNewContext( reader->config_doc );
	reader->name = strdup(name);
	reader->next = NULL;

	if( reader->xpathCx == NULL ) {
		fprintf( stderr, "config_reader_init(): Unable to create xpath context\n");
		return;
	}

	if( conf_reader == NULL ) {
		conf_reader = reader;
	} else {
		config_reader* tmp = conf_reader;
		conf_reader = reader;
		reader->next = tmp;
	}
}


char* config_value( const char* config_name, const char* xp_query, ... ) {

	if( conf_reader == NULL || xp_query == NULL ) {
		fatal_handler( "config_value(): NULL conf_reader or NULL param(s)" );
		return NULL;
	}

	config_reader* reader = conf_reader;
	while( reader != NULL ) {
		if( !strcmp(reader->name, config_name)) 
			break;
		reader = reader->next;
	}

	if( reader == NULL ) {
		fprintf(stderr, "No Config file with name %s\n", config_name );
		return NULL;
	}

	int slen = strlen(xp_query) + 512;/* this is unsafe ... */
	char xpath_query[ slen ]; 
	memset( xpath_query, 0, slen );
	va_list va_args;
	va_start(va_args, xp_query);
	vsprintf(xpath_query, xp_query, va_args);
	va_end(va_args);


	char* val;
	int len = strlen(xpath_query) + 100;
	char alert_buffer[len];
	memset( alert_buffer, 0, len );

	// build the xpath object
	xmlXPathObjectPtr xpathObj = xmlXPathEvalExpression( BAD_CAST xpath_query, reader->xpathCx );

	if( xpathObj == NULL ) {
		sprintf( alert_buffer, "Could not build xpath object: %s", xpath_query );
		fatal_handler( alert_buffer );
		return NULL;
	}


	if( xpathObj->type == XPATH_NODESET ) {

		// ----------------------------------------------------------------------------
		// Grab nodeset from xpath query, then first node, then first text node and 
		// finaly the text node's value
		// ----------------------------------------------------------------------------
		xmlNodeSet* node_list = xpathObj->nodesetval;
		if( node_list == NULL ) {
			sprintf( alert_buffer, "Could not build xpath object: %s", xpath_query );
			warning_handler(alert_buffer);
			return NULL;
		}

		if( node_list->nodeNr == 0 ) {
			sprintf( alert_buffer, "Config XPATH query  returned 0 results: %s", xpath_query );
			warning_handler(alert_buffer);
			return NULL;
		}


		xmlNodePtr element_node = *(node_list)->nodeTab;
		if( element_node == NULL ) {
			sprintf( alert_buffer, "Config XPATH query  returned 0 results: %s", xpath_query );
			warning_handler(alert_buffer);
			return NULL;
		}

		xmlNodePtr text_node = element_node->children;
		if( text_node == NULL ) {
			sprintf( alert_buffer, "Config variable has no value: %s", xpath_query );
			warning_handler(alert_buffer);
			return NULL;
		}

		val = text_node->content;
		if( val == NULL ) {
			sprintf( alert_buffer, "Config variable has no value: %s", xpath_query );
			warning_handler(alert_buffer);
			return NULL;
		}


	} else { 
		sprintf( alert_buffer, "Xpath evaluation failed: %s", xpath_query );
		warning_handler(alert_buffer);
		return NULL;
	}

	char* value = strdup(val);
	if( value == NULL ) { warning_handler( "config_value(): Empty config value or Out of Memory!" ); }

	// Free XPATH structures
	if( xpathObj != NULL ) xmlXPathFreeObject( xpathObj );

	return value;
}


void config_reader_free() {
	while( conf_reader != NULL ) {
		xmlXPathFreeContext( conf_reader->xpathCx );
		xmlFreeDoc( conf_reader->config_doc );
		free(conf_reader->name );
		config_reader* tmp = conf_reader->next;
		free( conf_reader );
		conf_reader = tmp;
	}
}

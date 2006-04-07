/* defines the currently used bootstrap config file */
#include "osrfConfig.h"

osrfConfig* __osrfConfigDefault = NULL;


void osrfConfigSetDefaultConfig(osrfConfig* cfg) {
	if(cfg) __osrfConfigDefault = cfg;
}

void osrfConfigFree(osrfConfig* cfg) {
	if(cfg) {
		jsonObjectFree(cfg->config);
		free(cfg->configContext);
		free(cfg);
	}	
}


int osrfConfigHasDefaultConfig() {
	return ( __osrfConfigDefault != NULL );
}


void osrfConfigCleanup() { 
	osrfConfigFree(__osrfConfigDefault); 
	__osrfConfigDefault = NULL; 
}


void osrfConfigReplaceConfig(osrfConfig* cfg, const jsonObject* obj) {
	if(!cfg || !obj) return;
	jsonObjectFree(cfg->config);
	cfg->config = jsonObjectClone(obj);	
}

osrfConfig* osrfConfigInit(char* configFile, char* configContext) {
	if(!configFile) return NULL;

	osrfConfigFree(__osrfConfigDefault);

	osrfConfig* cfg = safe_malloc(sizeof(osrfConfig));
	if(configContext) cfg->configContext = strdup(configContext);
	else cfg->configContext = NULL;

	xmlDocPtr doc = xmlParseFile(configFile);
	if(!doc) {
		osrfLogWarning( OSRF_LOG_MARK,  "Unable to parse XML config file %s", configFile);
		return NULL;
	}

	cfg->config = xmlDocToJSON(doc);
	xmlFreeDoc(doc);

	if(!cfg->config) {
		osrfLogWarning( OSRF_LOG_MARK, "xmlDocToJSON failed for config %s", configFile);
		return NULL;
	}	

	return cfg;
}

char* osrfConfigGetValue(osrfConfig* cfg, char* path, ...) {

	if(!path) return NULL;
	if(!cfg) cfg = __osrfConfigDefault;
	if(!cfg) { osrfLogWarning( OSRF_LOG_MARK, "No Confif object!"); return NULL; }

	VA_LIST_TO_STRING(path);

	jsonObject* obj;
	char* val = NULL;

	if(cfg->configContext) {
		obj = jsonObjectFindPath( cfg->config, "//%s%s", cfg->configContext, VA_BUF);
		if(obj) val = jsonObjectToSimpleString(jsonObjectGetIndex(obj, 0));

	} else {
		obj = jsonObjectFindPath( cfg->config, VA_BUF);
		if(obj) val = jsonObjectToSimpleString(obj);
	}

	jsonObjectFree(obj);
	return val;
}


int osrfConfigGetValueList(osrfConfig* cfg, osrfStringArray* arr, char* path, ...) {

	if(!arr || !path) return 0;
	if(!cfg) cfg = __osrfConfigDefault;
	if(!cfg) { osrfLogWarning( OSRF_LOG_MARK, "No Config object!"); return -1;}

	VA_LIST_TO_STRING(path);

	jsonObject* obj;
	if(cfg->configContext) {
		obj = jsonObjectFindPath( cfg->config, "//%s%s", cfg->configContext, VA_BUF);
	} else {
		obj = jsonObjectFindPath( cfg->config, VA_BUF);
	}

	int count = 0;

	if(obj && obj->type == JSON_ARRAY ) {

		int i;
		for( i = 0; i < obj->size; i++ ) {

			char* val = jsonObjectToSimpleString(jsonObjectGetIndex(obj, i));
			if(val) {
				count++;
				osrfStringArrayAdd(arr, val);
				free(val);
			}
		}
	}

	jsonObjectFree(obj);
	return count;
}


function go(){

load_lib('circ/circ_item_config.js');
load_lib('JSON_v1.js');
log_vars('circ_duration');


/* treat pre-cat copies like vanilla books */
if( isTrue(isPrecat) ) {
	log_info("pre-cat copy getting duration defaults...");
	result.durationRule			= 'default';
	result.recurringFinesRule	= 'default';
	result.maxFine	   			= 'default'
	return;
}


/* grab the config from the config script */
var config = getItemConfig();
var itemForm	= (marcXMLDoc) ? extractFixedField(marcXMLDoc,'Form') : "";


/* ----------------------------------------------------------------------------- 
	Now set the rule values based on the config.  If there is no configured info
	on this copy, fall back on defaults.
	----------------------------------------------------------------------------- */
if( config ) {

	log_debug("circ_duration found a config for the copy");
	result.durationRule			= config.durationRule;
	result.recurringFinesRule	= config.recurringFinesRule;
	result.maxFine			    = config.maxFine;

} else {

	result.durationRule = 'default';
	result.recurringFinesRule = 'default';
	result.maxFine = 'default';
}


log_info('final duration results: ' + 
    result.durationRule + ' : ' + result.recurringFinesRule + ' : ' + result.maxFine );

} go();





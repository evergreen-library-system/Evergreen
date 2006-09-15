function go(){

load_lib('circ/circ_item_config.js');
log_vars('circ_duration');


/* treat pre-cat copies like vanilla books */
if( isTrue(isPrecat) ) {
	log_info("pre-cat copy getting duration defaults...");
	result.durationRule			= '14_days_2_renew';
	result.recurringFinesRule	= '10_cent_per_day';
	result.maxFine					= 'overdue_mid';
	checkDurationExceptions();
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
	result.maxFine					= config.maxFine;

} else {

	result.durationRule			= '14_days_2_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.maxFine					= "overdue_mid";
}



/* ----------------------------------------------------------------------------- 
	Add custom rules here.  
	----------------------------------------------------------------------------- */

/* statelib has some special circ rules */

if( isOrgDescendent('STATELIB', copy.circ_lib.id) ) {

	result.durationRule			= '35_days_1_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.maxFine					= "overdue_mid";

	/* reference, microfiche, microfilm */
	if(	isTrue(copy.ref)	|| 
			itemForm == 'a'	|| 
			itemForm == 'b' ) {

		result.durationRule		= '14_days_2_renew';
	}	
}


checkDurationExceptions();

log_debug(result.durationRule + ' : ' + result.recurringFinesRule + ' : ' + result.maxFine );

} go();



function checkDurationExceptions() {
	log_debug("Checking duration rule exceptions for profile  "+patronProfile);

	if( isGroupDescendant('Staff', patronProfile) || isGroupDescendant('Outreach', patronProfile) ) {
		result.recurringFinesRule	= "staff";
		result.maxFine					= "staff";
	}

	if( isGroupDescendant('Outreach', patronProfile) ) {
		log_info("Outreach user found, setting duration to 2 months");
		result.durationRule = '2_months_2_renew';
	}
}


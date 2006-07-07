function go() {

/* load the script library */
load_lib('circ/circ_lib.js');
log_vars('circ_permit_patron');



if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');


/* ---------------------------------------------------------------------
	Check the items out count 
	--------------------------------------------------------------------- */
var config = findGroupConfig(patronProfile);
if( config ) {
	
	if( (config.maxItemsOut >= 0) && (patronItemsOut >= config.maxItemsOut) ) {
		result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
	}

} else {
	log_warn("** profile has no configured information: " + patronProfile);
}


} go();



function go() {

/* load the script library */
load_lib('circ_lib.js');
load_lib('circ_groups.js');

log_vars('circ_permit_patron');



if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');




/* ---------------------------------------------------------------------
	Check the items out count 
	--------------------------------------------------------------------- */
var config = findGroupConfig(patronProfile);
if( config ) {
	if( patronItemsOut >= 0 && patronItemsOut > config.maxIitemsOut )
		result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
} else {
	log_warn("** profile has no configured information: " + patronProfile);
}


} go();



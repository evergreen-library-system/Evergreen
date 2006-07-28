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
	
	var limit = config.maxItemsOut;
	if( limit >= 0 ) {

		/* a renewal does not add to the itemsOut, so just make
			sure they are not already over the items out limit */
		if( isTrue(isRenewal) ) {
			if( patronItemsOut > limit ) {
				result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
			}
		} else {
			if( patronItemsOut >= limit ) {
				result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
			}
		}
	}

} else {
	log_warn("** profile has no configured information: " + patronProfile);
}


} go();



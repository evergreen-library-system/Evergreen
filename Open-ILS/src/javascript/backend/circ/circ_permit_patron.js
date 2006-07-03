function go() {

/* load the script library */
load_lib('circ_lib.js');
log_vars('circ_permit_patron');


/* make sure they are not barred */
if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');


/* ---------------------------------------------------------------------
	Set up the limits for the various profiles.
	values of -1 mean there is no limit 
	--------------------------------------------------------------------- */
var PROFILES = {};
PROFILES['class']			= { itemsOutLimit : 10 };
PROFILES['patrons']		= { itemsOutLimit : 10 };
PROFILES['restricted']	= { itemsOutLimit : 2 };
PROFILES['circulators'] = { itemsOutLimit : -1 };
PROFILES['local system administrator'] = { itemsOutLimit : -1 };
/* add profiles as necessary ... */




/* ---------------------------------------------------------------------
	Check the items out count 
	--------------------------------------------------------------------- */
var profile = PROFILES[patronProfile];
if( profile ) {
	if( patronItemsOut > 0 && patronItemsOut > profile.itemsOutLimit )
		result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
} else {
	log_warn("profile has no configured information: " + patronProfile);
}


} go();



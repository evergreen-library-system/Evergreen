function go() {

/* load the lib script */
load_lib('../circ/circ_lib.js');
log_vars('patron_penalty');


var PROFILES = {};
PROFILES['class']			= { fineLimit : 10, overdueLimit : 10 };
PROFILES['patrons']		= { fineLimit : 10, overdueLimit : 10 };
PROFILES['restricted']	= { fineLimit : 0, overdueLimit : 0 };
PROFILES['circulators'] = { fineLimit : -1, overdueLimit : -1 };
PROFILES['local system administrator'] = { fineLimit : -1, overdueLimit : -1 };
/* add profiles as necessary ... */

var profile = PROFILES[patronProfile];

if( profile ) {

	/* check the fine limit */
	if( profile.fineLimit > 0 && patronFines >= profile.fineLimit )
		result.fatalEvents.push('PATRON_EXCEEDS_FINES');

	/* check the overdue limit */
	if( profile.overdueLimit > 0 && patronOverdueCount > profile.overdueLimit )
		result.fatalEvents.push('PATRON_EXCEEDS_OVERDUE_COUNT');

} else {
	log_warn("profile has no configured information: " + patronProfile);
}






} go();



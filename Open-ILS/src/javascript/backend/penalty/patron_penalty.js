function go() {

/* load the lib script */
load_lib('../circ/circ_lib.js');


/* collect some useful variables */
var patron					= environment.patron;
var patronProfile			= patron.profile.name.toLowerCase();
var patronFines			= environment.patronFines;
var patronOverdueCount	= environment.patronOverdueCount;


log_debug('Patron penalty script: ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	', Patron overdue: '		+ patronOverdueCount +
	'');


var PROFILES = {
	restricted : {
		fineLimit : 0,
		overdueLimit : 0,
	},
	patrons : {
		fineLimit : 10,
		overdueLimit : 10,
	},
	class : {
		fineLimit : 10,
		overdueLimit : 10,
	},
	'local system administrator' : {
		fineLimit : -1,
		overdueLimit : -1,
	}

	/* Add profiles as necessary ... */
}



var profile = PROFILES[patronProfile];

if( profile ) {

	/* check the fine limit */
	if( profile.fineLimit > 0 && patronFines >= profile.fineLimit )
		result.fatalEvents.push('PATRON_EXCEEDS_FINES');

	/* check the overdue limit */
	if( profile.overdueLimit > 0 && patronOverdueCount > profile.overdueLimit )
		result.fatalEvents.puth('PATRON_EXCEEDS_OVERDUE_COUNT');

} else {
	log_warn("profile has no configured information: " + patronProfile);
}






} go();



function go() {

/* load the lib script */
load_lib('../circ/circ_lib.js');


/* collect some useful variables */
var patron					= environment.patron;
var patronProfile			= patron.profile.name.toLowerCase();
var patronItemsOut		= environment.patronItemsOut;
var patronFines			= environment.patronFines;
var patronOverdueCount	= environment.patronOverdueCount;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
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
	}

	/* Add profiles as necessary ... */
}



/** Find the patron's profile and check the fine and overdue limits */
log_info(patronProfile);

var profile = PROFILES[patronProfile];
if( profile ) {
	if( patronFines >= profile.fineLimit )
		result.events.push('PATRON_EXCEEDS_FINES');
	if( patronOverdueCount > profile.overdueLimit )
		result.events.puth('REFUND_EXCEEDS_OVERDUE_COUNT');
}





} go();



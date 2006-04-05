function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var patron				= environment.patron;
var patronProfile		= patron.profile.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	'');


if( patronProfile == 'patrons' && patronItemsOut > 10 )
	result.fatalEvents.push('PATRON_EXCEEDS_CHECKOUT_COUNT');

if( patronProfile == 'staff' && patronItemsOut > 30 )
	result.fatalEvents.push('PATRON_EXCEEDS_CHECKOUT_COUNT');


/* test */
result.fatalEvents.push('TEST_FATAL_EVENT');
result.infoEvents.push('TEST_INFO_EVENT');
/* ---- */


} go();



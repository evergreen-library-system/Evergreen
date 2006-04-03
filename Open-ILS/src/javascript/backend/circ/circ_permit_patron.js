function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var patron				= environment.patron;
var patronStanding	= patron.standing.value.toLowerCase();
var patronProfile		= patron.profile.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron Standing: '	+ patronStanding +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');


if( patronStanding != 'good' ) 
	result.events.push('PATRON_BAD_STANDING');

if( patronProfile == 'patrons' && patronItemsOut > 10 )
	result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');

if( patronProfile == 'staff' && patronItemsOut > 30 )
	result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');


} go();



function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var patron		= environment.patron;
var standing	= patron.standing.value.toLowerCase();
var profile		= patron.profile.name.toLowerCase();
var itemsOut	= environment.patronItemsOut;
var fines		= environment.patronFines;
var isRenewal	= environment.isRenewal;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patron.profile.name +
	', Patron Standing: '	+ patron.standing.value +
	', Patron copies: '		+ itemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ fines +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');



if( standing != 'good' ) 
	return result.event = 'PATRON_BAD_STANDING';

if( profile == 'patrons' && itemsOut > 10 )
	return result.event = 'PATRON_EXCEEDS_CHECKOUT_COUNT';

if( profile == 'staff' && itemsOut > 30 )
	return result.event = 'PATRON_EXCEEDS_CHECKOUT_COUNT';


} go();



function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var patron				= environment.patron;
var patronProfile		= patron.profile.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');


if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');


/* define the items out limits */
var PROFILES = {

	restricted : {
		itemsOutLimit : 2,
	},
	patrons : {
		itemsOutLimit : 10,
	},
	'class' : {
		itemsOutLimit : 10,
	},
	'local system administrator' : {
		itemsOut : -1,
	},
	circulators : {
		itemsOut : -1,
	}


	/* Add profiles as necessary ... */
}


var profile = PROFILES[patronProfile];
if( profile ) {
	if( patronItemsOut > 0 && patronItemsOut > profile.itemsOutLimit )
		result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
} else {
	log_warn("profile has no configured information: " + patronProfile);
}


} go();



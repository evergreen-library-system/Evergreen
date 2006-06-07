function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var patron				= environment.patron;
//var patronStanding	= patron.standing.value.toLowerCase();
var patronProfile		= patron.profile.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;


log_debug('circ_permit_patron: permit circ on ' +
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
//	', Patron Standing: '	+ patronStanding +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');


log_debug("BARRED: " + patron.barred );

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
	class : {
		itemsOutLimit : 10,
	}

	/* Add profiles as necessary ... */
}


var profile = PROFILES[patronProfile];
if( profile ) {
	if( patronItemsOut > profile.itemsOutLimit )
		result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
}


} go();



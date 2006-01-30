function go() {

/* load the lib script */
load_lib('circ_lib.js');


/* collect some useful variables */
var copy			= environment.copy;
var patron		= environment.patron;
var standing	= patron.standing.value.toLowerCase();
var profile		= patron.profile.name.toLowerCase();
var status		= copy.status.name.toLowerCase();
var itemsOut	= environment.patronItemsOut;
var fines		= environment.patronFines;
var isRenewal	= environment.isRenewal;


log_debug('circ_permit_copy: permit circ on ' +
	' Copy: '					+ copy.id + 
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patron.profile.name +
	', Patron Standing: '	+ patron.standing.value +
	', Patron copies: '		+ itemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ fines +
	', Copy status: '			+ copy.status.name +
	', Copy location: '		+ copy.location.name +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');



if( copy.circulate == '0' ) 
	return result.event = 'COPY_CIRC_NOT_ALLOWED';

if( copy.ref != '0' ) 
	return result.event = 'COPY_IS_REFERENCE';

if( status != 'available' && status != 'on holds shelf' )
	return result.event = 'COPY_NOT_AVAILABLE';

var holds = copy.fetchHold();
for( var i in holds ) {
	var hold = holds[i];
	if( hold && hold.usr != patron.id )
		return result.event = 'COPY_NEEDED_FOR_HOLD';
}


} go();



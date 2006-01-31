function go() {

/* load the lib script */
load_lib('circ_lib.js');

/* collect some useful variables */
var copy					= environment.copy;
var patron				= environment.patron;
var patronStanding	= patron.standing.value.toLowerCase();
var patronProfile		= patron.profile.name.toLowerCase();
var copyStatus			= copy.status.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;


log_debug('circ_permit_copy: permit circ on ' +
	' Copy: '					+ copy.id + 
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Profile: '		+ patronProfile +
	', Patron Standing: '	+ patronStanding +
	', Patron copies: '		+ patronItemsOut +
	', Patron Library: '		+ patron.home_ou.name +
	', Patron fines: '		+ patronFines +
	', Copy status: '			+ copyStatus +
	', Copy location: '		+ copy.location.name +
	', Is Renewal: '			+ ( (isRenewal) ? "yes" : "no" ) +
	'');



if( copy.circulate == '0' ) 
	return result.event = 'COPY_CIRC_NOT_ALLOWED';

if( copy.ref != '0' ) 
	return result.event = 'COPY_IS_REFERENCE';

if( copyStatus != 'available' && copyStatus != 'on holds shelf' )
	return result.event = 'COPY_NOT_AVAILABLE';

/* example of handling holds 
var holds = copy.fetchHold();
for( var i in holds ) {
	var hold = holds[i];
	if( hold && hold.usr != patron.id )
		return result.event = 'COPY_NEEDED_FOR_HOLD';
}
*/


} go();



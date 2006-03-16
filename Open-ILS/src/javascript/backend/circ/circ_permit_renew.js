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

var holds = copy.fetchHolds();
for( var i in holds ) {
	var hold = holds[i];
	if( hold && hold.usr != patron.id )
		return result.event = 'COPY_NEEDED_FOR_HOLD';
}

} go();

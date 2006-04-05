
function go() {

/* load the lib script */
load_lib('circ_lib.js');

/* collect some useful variables */
var copy					= environment.copy;
var patron				= environment.patron;
var patronProfile		= patron.profile.name.toLowerCase();
var copyStatus			= copy.status.name.toLowerCase();
var patronItemsOut	= environment.patronItemsOut;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;


/* set sane defaults */
result.durationLevel	= copy.loan_duration;
result.durationRule	= "2wk_default";





return;


} go();

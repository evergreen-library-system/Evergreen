function go() {

/* load the script library */
load_lib('circ/circ_lib.js');
log_vars('circ_permit_patron');


if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

var config = findGroupConfig(patronProfile);
/* inspect the config too see if this patron should be allowed */


} go();



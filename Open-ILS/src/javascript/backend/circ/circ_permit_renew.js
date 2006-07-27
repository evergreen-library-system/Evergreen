function go() {

/* load the lib script */
load_lib('circ/circ_lib.js');
log_vars('circ_permit_renew');

var holds = copy.fetchHolds();
for( var i in holds ) {
	log_info("hold found for renewal item, checking hold->usr..");
	var hold = holds[i];
	if( hold && hold.usr != patron.id )
		return result.events.push('COPY_NEEDED_FOR_HOLD');
}

} go();

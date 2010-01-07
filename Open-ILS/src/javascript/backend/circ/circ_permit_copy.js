function go() {

/* load the lib script */
load_lib('circ/circ_lib.js');
load_lib('JSON_v1.js');
log_vars('circ_permit_copy');


if( ! isTrue(copy.circulate) || !isTrue(copy.location.circulate) ) 
	result.events.push('COPY_CIRC_NOT_ALLOWED');


if( ! isTrue(isRenewal) ) {
	if(copyStatus != 'Available' && 
		copyStatus != 'On holds shelf' && copyStatus != 'Reshelving' ) {
			result.events.push('COPY_NOT_AVAILABLE');
	} 
}


	
} go();



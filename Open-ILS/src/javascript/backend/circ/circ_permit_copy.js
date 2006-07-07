function go() {

/* load the lib script */
load_lib('circ/circ_lib.js');
log_vars('circ_permit_copy');


if( ! isTrue(copy.circulate) ) 
	result.events.push('COPY_CIRC_NOT_ALLOWED');


if( ! isOrgDescendent( 'STATELIB', copy.circ_lib.id ) ) {
	if( isTrue(copy.ref) ) 
		result.events.push('COPY_IS_REFERENCE');
}



if(copyStatus != 'Available' && 
	copyStatus != 'On holds shelf' && copyStatus != 'Reshelving' ) {
		result.events.push('COPY_NOT_AVAILABLE');
}


/* this should happen very rarely .. 
	but it should at least require an override */


if( getMARCItemType() == 'g' 
	&& copy.circ_lib.id != patron.home_ou.id )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');


	
} go();



function go() {

/* load the lib script */
load_lib('circ_lib.js');
log_vars('circ_permit_copy');



if( ! isTrue(copy.circulate) ) 
	result.events.push('COPY_CIRC_NOT_ALLOWED');

if( isTrue(copy.ref) ) 
	result.events.push('COPY_IS_REFERENCE');



if(copyStatus != 'available' && 
	copyStatus != 'on holds shelf' && copyStatus != 'reshelving' ) {
		result.events.push('COPY_NOT_AVAILABLE');
}

/* this should happen very rarely .. but it needs to be protected */
if( recDescriptor.item_type == 'g'  /* projected medium */
	&& copy.circ_lib != patron.home_ou.id )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');



	
} go();



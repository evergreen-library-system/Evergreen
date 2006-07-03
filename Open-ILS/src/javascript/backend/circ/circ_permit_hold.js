
function go() {

load_lib('circ_lib.js');
log_vars('circ_permit_hold');



if( recDescriptor.item_type == 'g'  /* projected medium */
	&& copy.circ_lib != patron.home_ou.id )
	return result.event = 'CIRC_EXCEEDS_COPY_RANGE';


return result.event = 'SUCCESS';


} go();


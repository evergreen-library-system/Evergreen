
function go() {

load_lib('circ_lib.js');
load_lib('circ_groups.js');
load_lib('../catalog/record_type.js');
log_vars('circ_permit_hold');



/* projected medium */
if( extractFixedField(marcXMLDoc, 'Type') == 'g' 
	&& copy.circ_lib != patron.home_ou.id )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');



} go();


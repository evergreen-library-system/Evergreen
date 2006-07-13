
function go() {

load_lib('circ/circ_lib.js');
log_vars('circ_permit_hold');



/* projected medium */
if( getMARCItemType() == 'g' &&
		!isOrgDescendent(copy.circ_lib.shortname, patron.home_ou.id) )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');



} go();


function go() {

load_lib('circ/circ_lib.js');
log_vars('circ_permit_hold');


if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

if( isTrue(copy.ref) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

if( !isTrue(copy.circulate) ) 
	result.events.push('ITEM_NOT_HOLDABLE');


} go();




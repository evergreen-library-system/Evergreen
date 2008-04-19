function go() {

load_lib('circ/circ_lib.js');
load_lib('JSON_v1.js');
log_vars('circ_permit_hold');



if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

if( isTrue(copy.ref) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

if( !isTrue(copy.circulate) ) 
	result.events.push('ITEM_NOT_HOLDABLE');


var config = findGroupConfig(patronProfile);


if( config ) {

    /* see if they have too many items out */
    if(newHold) {
        log_info("This is a new hold, checking maxHolds...");
        var limit = config.maxHolds;
        var count = userHoldCount(patron.id);
        if( limit >= 0 && count >= limit ) {
            log_info("patron has " + count + " open holds");
            result.events.push('MAX_HOLDS');
        }
    } else {
        log_info("Ignoring maxHolds on existing hold...");
    }
}


} go();




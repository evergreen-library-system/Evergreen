function go() {

/* load the script library */
load_lib('circ/circ_lib.js');
load_lib('JSON_v1.js');
log_vars('circ_permit_patron');


if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

var config = findGroupConfig(patronProfile);

if( config ) {

    var limit = config.maxItemsOut;
    if( limit >= 0 ) {
        log_info('patron items out = ' + patronItemsOut +' limit = ' + limit);
        if( !isTrue(isRenewal) && patronItemsOut >= limit ) {
            result.events.push('PATRON_EXCEEDS_CHECKOUT_COUNT');
        }
    }
    
} else {

    log_warn("** profile has no configured information: " + patronProfile);
}



} go();



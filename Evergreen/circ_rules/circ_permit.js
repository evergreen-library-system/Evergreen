function go() {

log_debug('Checking permit circ on ' +
	' Copy: '				+ copy.id + 
	' Patron:'				+ patron.id +
	' Patron Profile: '	+ patron.profile +
	' Patron Standing: ' + patron.standing +
	' Patron copies: '	+ patron_info.items_out +
	' Patron fines: '		+ patron_info.fines );


/* Patron checks --------------------------------------------- */
if( ! patron.standing.match(/good/i) ) 
	return result.event = 'PATRON_BAD_STANDING';

if( patron.profile.match(/patrons/i) && patron_info.items_out > 10 )
	return result.event = 'PATRON_EXCEEDS_CHECKOUT_COUNT';

if( patron.profile.match(/staff/i) && patron_info.items_out > 30 )
	return result.event = 'PATRON_EXCEEDS_CHECKOUT_COUNT';


/* Copy checks ------------------------------------------------ */
if( is_false( copy.circulate ) ) 
	return result.event = 'COPY_CIRC_NOT_ALLOWED';

/* check for holds -------------------------------------------- */
fetch_hold_by_copy( copy.id );
if( hold && hold.usr != patron.id )
	return result.event = 'COPY_NEEDED_FOR_HOLD';


} go();



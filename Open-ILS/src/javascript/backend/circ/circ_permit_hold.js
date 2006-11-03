function go() {

load_lib('circ/circ_lib.js');
log_vars('circ_permit_hold');

if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

if( isTrue(copy.ref) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

if( !isTrue(copy.circulate) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

/* all STATELIB items are holdable regardless of type */
if( isOrgDescendent('STATELIB', copy.circ_lib.id) ) return;

var mod = (copy.circ_modifier) ? copy.circ_modifier.toLowerCase() : "";

log_info("circ-modifier = "+mod);

if( mod == 'bestsellernh' )
	result.events.push('ITEM_NOT_HOLDABLE');

var marcItemType = getMARCItemType();
var isAnc;

if( ( marcItemType == 'g' || 
		marcItemType == 'i' || 
		marcItemType == 'j' || 
		mod == 'softwrlong' || 
		mod == 'music' || 
		mod == 'audiobook' || 
		mod == 'av' || 
		mod == 'cd' || 
		mod == 'kit' || 
		mod == 'dvd' || 
		mod == 'deposit' || 
		mod == 'atlas' || 
		mod == 'magazine' || 
		mod == 'equipment' || 
		mod == 'equip-long' || 
		mod == 'microform' || 
		mod == 'record' || 
		isTrue(copy.deposit) || 
		mod == 'video-long' || 
		mod == 'video' ) ) {

	isAnc = hasCommonAncestor( copy.circ_lib.id, patron.home_ou.id, 1 );

	if( isAnc) {
		log_info("patron and copy circ_lib share a common ancestor, hold allowed");

	} else {
		log_info("patron and copy circ_lib do NOT share a common ancestor");

		if( hasCommonAncestor( copy.circ_lib.id, holdRequestLib.id, 1) ) {
			log_info("request_lib and copy circ_lib DO share a common ancestor");

		} else {

			log_info("request_lib and copy circ_lib also do NOT share a common ancestor, hold on this type of material not allowed");
			result.events.push('ITEM_NOT_HOLDABLE');
		}
	}
}


} go();


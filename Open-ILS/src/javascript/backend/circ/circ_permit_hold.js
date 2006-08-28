function go() {

load_lib('circ/circ_lib.js');
log_vars('circ_permit_hold');

if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

/* projected medium 
	this needs to be expanded to check circ_modifiers as well
*/

var mod = (copy.circ_modifier) ? copy.circ_modifier.toLowerCase() : "";

log_info("circ-modifier = "+mod);


if( mod == 'bestsellernh' )
	result.events.push('ITEM_NOT_HOLDABLE');

if( ( getMARCItemType() == 'g' || 
		mod == 'audiobook' || 
		mod == 'av' || 
		mod == 'cd' || 
		mod == 'dvd' || 
		mod == 'video' ) &&

		!isOrgDescendent(copy.circ_lib.shortname, patron.home_ou.id) ) {

	log_info("This patron may not place a hold on the selected item");

	result.events.push('ITEM_NOT_HOLDABLE');
}


} go();


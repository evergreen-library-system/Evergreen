function go() {

load_lib('circ/circ_lib.js');
log_vars('circ_permit_hold');


/* is a staff member placing this hold? */
var isStaffHold = isGroupDescendantId('Staff', requestor.profile);


/* non-staff members are allowed 50 open holds at most */
if( ! isStaffHold ) {
   var count = userHoldCount(patron.id);
   log_info("patron has " + count + " open holds");
   if( count >= 50 ) 
      result.events.push('MAX_HOLDS');
} else {
    log_info("This is a staff-placed hold");
}



if( isTrue(patron.barred) ) 
	result.events.push('PATRON_BARRED');

if( isTrue(copy.ref) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

if( !isTrue(copy.circulate) ) 
	result.events.push('ITEM_NOT_HOLDABLE');

/* all STATELIB items are holdable regardless of type */
if( isOrgDescendent('STATELIB', copy.circ_lib.id) ) return;


var mod = (copy.circ_modifier) ? copy.circ_modifier.toLowerCase() : "";
var marcItemType = getMARCItemType();


log_info("circ-modifier = "+mod);
log_info("marc-type = "+marcItemType);


if( mod == 'bestsellernh' )
	result.events.push('ITEM_NOT_HOLDABLE');


if( ( marcItemType == 'g' || 
		marcItemType == 'i' || 
		marcItemType == 'j' || 
		mod == 'softwrlong' || 
		mod == 'music' || 
		mod == 'audiobook' || 
		mod == 'av' || 
		mod == 'new-av' || 
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


	log_info("this is a range-protected item...");

	/* ------------------------------------------------------------------------ */
	/** This patch allows DCPL and LEE patrons to place 
		holds on protected items accross their systems.  In short, if the pickup lib,
		owning lib, and patron home (or request lib) are all within either of the two 
		systems, allow the hold */
	if(
		/* DCPL=33, LEE=115 */
		(hasCommonAncestor(holdPickupLib, 33, 1) || hasCommonAncestor(holdPickupLib, 115, 1)) &&
		(hasCommonAncestor(volume.owning_lib, 33, 1) || hasCommonAncestor(volume.owning_lib, 115, 1)) &&
		(
			hasCommonAncestor(patron.home_ou.id, 33, 1) || hasCommonAncestor(patron.home_ou.id, 115, 1) || 
			hasCommonAncestor(holdRequestLib.id, 33, 1) || hasCommonAncestor(holdRequestLib.id, 115, 1)
		)) {

		log_info("DCPL and LEE are allowed to place holds on protected items accross the two systems");
		return;
	}
	/* ------------------------------------------------------------------------ */


    if( ! hasCommonAncestor( volume.owning_lib, holdPickupLib, 1 ) ) {

        /* we don't want these items to transit to the pickup lib */
        result.events.push('ITEM_NOT_HOLDABLE');
	    log_info("pickup_lib is not in the owning_lib's region...NOT OK");

    } else { /* pickup lib is in the owning region */

        if( isStaffHold && hasCommonAncestor( volume.owning_lib, holdRequestLib.id, 1) ) {

            /* staff in the region can place holds for patrons outside the region with local pickup lib */
            log_info("local, staff-placed hold is allowed with local pickup_lib...OK");

        } else {

            if( hasCommonAncestor( volume.owning_lib, patron.home_ou.id, 1 ) ) {

                /* patrons can hold the item if they are registered 
                    in the region and pickup lib is local */  
                log_info("patron's home_ou is in the owning region...OK");

            } else {

                log_info("patron's home_ou lies outside the owning region...NOT OK");
                result.events.push('ITEM_NOT_HOLDABLE');
            }
        }
    }
}




} go();




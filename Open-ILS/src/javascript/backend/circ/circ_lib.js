load_lib('catalog/record_type.js');
load_lib('circ/circ_groups.js');
load_lib('JSON_v1.js');


try {
	if( environment.copy ) {
		environment.copy.fetchBestHold = function() {
			var key = scratchKey();
			environment.copy.__OILS_FUNC_fetch_best_hold(scratchPad(key));
			var val = getScratch(key);
			return (val) ? val : null;
		}
	}
} catch(e) {}


/* ----------------------------------------------------------------------------- 
	Collect all of the global variables
	----------------------------------------------------------------------------- */

/* the global result object.  Any data returned to the 
	caller must be put into this object.  */
var result				= environment.result = {};
result.event			= 'SUCCESS';
result.events			= [];
result.fatalEvents	= [];
result.infoEvents		= [];


/* Pull in any variables passed in from the calling process */
var copy					= environment.copy;
var volume				= environment.volume;
var title				= environment.title;
var recDescriptor		= environment.titleDescriptor;
var patron				= environment.patron;
var patronItemsOut	= environment.patronItemsOut;
var patronOverdueCount	= environment.patronOverdueCount;
var patronFines		= environment.patronFines;
var isRenewal			= environment.isRenewal;
var isPrecat			= environment.isPrecat;
var currentLocation	= environment.location;
var holdRequestLib	= environment.requestLib;
var holdPickupLib       = environment.pickupLib; /* hold pickup lib */
var requestor = environment.requestor || patron;
var newHold = environment.newHold;



/* create some new vars based on the data we have wherever possible */
var patronProfile;
var copyStatus;
var marcXMLDoc;

if( patron && patron.profile ) 
	patronProfile = patron.profile.name;
if( copy && copy.status ) 
	copyStatus = copy.status.name;
if( title && title.marc )
	marcXMLDoc = new XML(title.marc);



/* copy the group tree into some other useful data structures */
var groupTree		= environment.groupTree;
var groupList		= {};
var groupIDList	= {};
flattenGroupTree(groupTree);






/* ----------------------------------------------------------------------------- 
	Define all of the utility functions
	----------------------------------------------------------------------------- */



/* useful functions for creating wrappers around system functions */
var __scratchKey = 0;
var __SCRATCH = {};
function scratchKey()		{ return '_' + __scratchKey++; };
function scratchPad(key)	{ return '__SCRATCH.'+ key; }
function getScratch(key)	{ return __SCRATCH[ key ]; }
function scratchClear()		{ for( var o in __SCRATCH ) __SCRATCH[o] = null; }


/* note: returns false if the value is 'f' or 'F' ... */
function isTrue(d) {
	if(	d && 
			d != "0" && 
			d != "f" &&
			d != "F" )
			return true;
	return false;
}

/* Utility function for iterating over array */
function iterate( arr, callback ) {
	for( var i = 0; i < arr.length; i++ ) 
		callback(arr[i]);
}


/**
  * returns a list of items that when passed to the callback 
  * 'func' returned true returns null if none were found
  */
function grep( arr, func ) {
	var results = [];
	iterate( arr, 
		function(d) {
			if( func(d) ) 
				results.push(d);
		}
	);
	if(results.length > 0)	
		return results;
	return null;
}



function flattenGroupTree(node) {
	if(!node) return null;
	groupList[node.name] = node;
	groupIDList[node.id] = node;
	iterate( node.children,
		function(n) {
			flattenGroupTree(n);
		}
	);
}



/**
  * Returns true if 'child' is equal or descends from 'parent'
  * @param parent The name of the parent group
  * @param child The name of the child group
  */
function isGroupDescendant( parent, child ) {
	log_debug("checking descendant p="+parent + " c=" + child);
	return __isGroupDescendant(
		groupList[parent],
		groupList[child]);
}

function isGroupDescendantId( parentName, childId ) {
	log_debug("checking descendant ID p="+parentName + " c=" + childId);
	return __isGroupDescendant(
		groupList[parentName],
		groupIDList[childId]);
}


/**
  * Returns true if 'child' is equal or descends from 'parent'
  * @param parent The node of the parent group
  * @param child The node of the child group
  */
function __isGroupDescendant( parent, child ) {
    if(!(parent && child)) return false;
	if (parent.id == child.id) return true;
	var node = child;
	while( (node = groupIDList[node.parent]) ) {
		if( node.id == parent.id ) 
			return true;
	}
	return false;
}


function getMARCItemType() {
	if(	copy &&
			copy.circ_as_type &&
			copy.circ_as_type != 'undef' )
		return copy.circ_as_type;
	
	return (marcXMLDoc) ? extractFixedField(marcXMLDoc, 'Type') : "";
}


function isOrgDescendent( parentName, childId ) {
	var key = scratchKey();
	__OILS_FUNC_isOrgDescendent(scratchPad(key), parentName, childId);
	var val = getScratch(key);
	if( val == '1' ) return true;
	return false;
}

/* returns the number of unfulfilled holds open on this user */
function userHoldCount(userid) {
   var key = scratchKey();
   __OILS_FUNC_userHoldCount(scratchPad(key), userid);
   return getScratch(key);
}

function hasCommonAncestor( org1, org2, depth ) {
	var key = scratchKey();
	__OILS_FUNC_hasCommonAncestor(scratchPad(key), org1, org2, depth);
	var val = getScratch(key);
	if( val == '1' ) return true;
	return false;
}

/* returns a dictionary of circmod : count for checked out items */
function checkoutsByCircModifier(userid) {
    var key = scratchKey();
    __OILS_FUNC_userCircsByCircmod(scratchPad(key), userid);
    var val = getScratch(key);
    return (val) ? val : {};
}

/* useful for testing */
function die(msg) {
	log_error("die(): "+msg);
	log_stderr("die(): "+msg);
	var foo = null;
	var baz = foo.bar;
}



/* logs a load of info */
function log_vars( prefix ) {
	var str = prefix + ' : ';

	if(patron) {
		str += ' Patron=' + patron.id;
		str += ', Patron_Username='+ patron.usrname;
		str += ', Patron_Profile_Group='+ patronProfile;
		str += ', Patron_Fines='	+ patronFines;
		str += ', Patron_OverdueCount='	+ patronOverdueCount;
		str += ', Patron_Items_Out=' + patronItemsOut;

		try {
			str += ', Patron_Barcode='	+ patron.card.barcode;
			str += ', Patron_Library='	+ patron.home_ou.name;
		} catch(e) {}
	}

    if(requestor.id != patron.id) 
        str+= ' Requestor='+requestor.usrname;

	if(copy)	{
		str += ', Copy=' + copy.id;
		str += ', Copy_Barcode=' + copy.barcode;
		str += ', Copy_status='	+ copyStatus;
      str += (copy.circ_modifier) ? ', Circ_Mod=' + copy.circ_modifier : '';

		try {
			str += ', Circ_Lib=' + copy.circ_lib.shortname;
			str += ', Copy_location=' + copy.location.name;
		} catch(e) {}
	}

	if(volume) {
        str += ', Item_Owning_lib=' + volume.owning_lib;
        str += ', Volume='	+ volume.id;
    }

	if(title) str += ', Record='	+ title.id;

	if(recDescriptor)	{
		str += ', Record_Descriptor=' + recDescriptor.id;
		str += ', Item_Type='			+ recDescriptor.item_type;
		str += ', Item_Form='			+ recDescriptor.item_form;
		str += ', Item_Lang='			+ recDescriptor.item_lang;
		str += ', Item_Audience='		+ recDescriptor.audience;
	}

	str += ', Is_Renewal: '	+ ( (isTrue(isRenewal)) ? "yes" : "no" );
	str += ', Is_Precat: '	+ ( (isTrue(isPrecat)) ? "yes" : "no" );
	str += (holdRequestLib) ? ', Hold_request_lib=' + holdRequestLib.shortname : '';
    str += (holdPickupLib) ? ', Hold_Pickup_Lib=' + holdPickupLib : '';

	log_info(str);
}



/**
  * Returns config information for the requested group.  If 
  * no config info exists for the requested group, then this
  * function searches up the tree to find the config info 
  * for the nearest ancestor
  * @param The name of the group who's config info to return
  */
function findGroupConfig(name) {
	if(!name) return null;
	var node = groupList[name];
	do {
		if( GROUP_CONFIG[node.name] ) {
			debugGroupConfig(name, node.name, GROUP_CONFIG[node.name]);
			return GROUP_CONFIG[node.name];
		}
	} while( (node = groupIDList[node.parent]) );
	return null;
}


/** prints out the settings for the given group config **/
function debugGroupConfig(name, foundName, config) {
	if(!config) return;
	var str = "findGroupConfig('"+name+"'): returning config info for '"+ foundName +"': ";
	for( var i in config ) 
		str += i + '=' + config[i] + '  ';
	log_debug(str);
}



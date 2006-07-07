load_lib('catalog/record_type.js');
load_lib('circ/circ_groups.js');

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
var isRenewal			= environment.isRenewal;
var patronItemsOut	= environment.patronItemsOut;
var patronOverdueCount	= environment.patronOverdueCount;
var patronFines		= environment.patronFines;



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
	return __isGroupDescendant(
		groupList[parent],
		groupList[child]);
}



/**
  * Returns true if 'child' is equal or descends from 'parent'
  * @param parent The node of the parent group
  * @param child The node of the child group
  */
function __isGroupDescendant( parent, child ) {
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
	
	return extractFixedField(marcXMLDoc, 'Type');
}


function isOrgDescendent( parentName, childId ) {
	var key = scratchKey();
	__OILS_FUNC_isOrgDescendent(scratchPad(key), parentName, childId);
	var val = getScratch(key);
	if( val == '1' ) return true;
	return false;
}
	



/*
- at some point we should add a library of objects that map 
codes to names (item_form, item_type, etc.)
load_lib('item_form_map.js');
var form_name = item_form_map[env.record_descriptor.item_form];
*/



/* logs a load of info */
function log_vars( prefix ) {
	var str = prefix + ' : ';

	if(patron) {
		str += ' Patron=' + patron.id;
		str += ', Patron Barcode='	+ patron.card.barcode;
		str += ', Patron Username='+ patron.usrname;
		str += ', Patron Profile Group='+ patronProfile;
		str += ', Patron Library='	+ patron.home_ou.name;
		str += ', Patron Fines='	+ patronFines;
		str += ', Patron OverdueCount='	+ patronOverdueCount;
		str += ', Patron Items Out=' + patronItemsOut;
	}

	if(copy)	{
		str += ', Copy=' + copy.id;
		str += ', Copy Barcode=' + copy.barcode;
		str += ', Copy status='	+ copyStatus;
		str += ', Copy location=' + copy.location.name;
	}

	if(volume)			str += ', Volume='	+ volume.id;
	if(title)			str += ', Record='	+ title.id;

	if(recDescriptor)	{
		str += ', Record Descriptor=' + recDescriptor.id;
		str += ', Item Type='			+ recDescriptor.item_type;
		str += ', Item Form='			+ recDescriptor.item_form;
		str += ', Item Lang='			+ recDescriptor.item_lang;
		str += ', Item Audience='		+ recDescriptor.audience;
	}

	str += ' Is Renewal: '	+ ( (isTrue(isRenewal)) ? "yes" : "no" );

	log_debug(str);
}




var __scratchKey = 0;
var __SCRATCH = {};

/* useful functions for creating wrappers around system functions */
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



/* collect the useful variables */
var result				= environment.result = {};
result.event			= 'SUCCESS';
result.events			= [];
result.fatalEvents	= [];
result.infoEvents		= [];

var copy					= environment.copy;
var volume				= environment.volume;
var title				= environment.title;
var recDescriptor		= environment.titleDescriptor;
var patron				= environment.patron;
var isRenewal			= environment.isRenewal;
var patronItemsOut	= environment.patronItemsOut;
var patronOverdueCount	= environment.patronOverdueCount;
var patronFines		= environment.patronFines;
var patronProfile;
var copyStatus;

if( patron.profile ) patronProfile = patron.profile.name.toLowerCase();
if( copy.status ) copyStatus = copy.status.name.toLowerCase();



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



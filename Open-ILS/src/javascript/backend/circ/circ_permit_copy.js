function go() {

/* load the lib script */
load_lib('circ_lib.js');

/* collect some useful variables */
var copy					= environment.copy;
var patron				= environment.patron;
var volume				= environment.volume;
var title				= environment.title;
var recDescriptor		= environment.titleDescriptor;
var patronProfile		= patron.profile.name.toLowerCase();
var copyStatus			= copy.status.name.toLowerCase();
var isRenewal			= environment.isRenewal;

/*
- at some point we should add a library of objects that map 
codes to names (item_form, item_type, etc.)
load_lib('item_form_map.js');
var form_name = item_form_map[env.record_descriptor.item_form];
*/


log_debug('circ_permit_copy: permit circ on ' +
	'  Copy: '					+ copy.id + 
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Library: '		+ patron.home_ou.name +
	', Copy status: '			+ copyStatus +
	', Copy location: '		+ copy.location.name +
	', Is Renewal: '			+ ( (isTrue(isRenewal)) ? "yes" : "no" ) +
	', Item Type: '			+ recDescriptor.item_type +
	', Item Form: '			+ recDescriptor.item_form +
	', Item Lang: '			+ recDescriptor.item_lang +
	', Item Audience: '		+ recDescriptor.audience +
	'');



if( ! isTrue(copy.circulate) ) 
	result.events.push('COPY_CIRC_NOT_ALLOWED');

if( isTrue(copy.ref) ) 
	result.events.push('COPY_IS_REFERENCE');



if(copyStatus != 'available' && 
	copyStatus != 'on holds shelf' && copyStatus != 'reshelving' ) {
		result.events.push('COPY_NOT_AVAILABLE');
}

/* this should happen very rarely .. but it needs to be protected */
if( recDescriptor.item_type == 'g'  /* projected medium */
	&& copy.circ_lib != patron.home_ou.id )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');



	
} go();



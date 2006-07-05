function go() {

/* load the lib script */
load_lib('circ_lib.js');
load_lib('circ_groups.js');
load_lib('../catalog/record_type.js');

log_vars('circ_permit_copy');


if( ! isTrue(copy.circulate) ) 
	result.events.push('COPY_CIRC_NOT_ALLOWED');

if( isTrue(copy.ref) ) 
	result.events.push('COPY_IS_REFERENCE');



if(copyStatus != 'Available' && 
	copyStatus != 'On holds shelf' && copyStatus != 'Reshelving' ) {
		result.events.push('COPY_NOT_AVAILABLE');
}

var type = extractFixedField(marcXMLDoc, 'Type');
log_stdout('type = ' + type);

/* this should happen very rarely .. but it should at least require an override */
if( extractFixedField(marcXMLDoc, 'Type') == 'g' 
	&& copy.circ_lib != patron.home_ou.id )
	result.events.push('CIRC_EXCEEDS_COPY_RANGE');


	
} go();



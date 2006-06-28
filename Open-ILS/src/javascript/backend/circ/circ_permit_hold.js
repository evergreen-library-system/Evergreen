function go() {

var patron				= environment.patron;
var title				= environment.title;
var copy					= environment.copy;
var volume				= environment.volume;
var title				= environment.title;
var requestor			= environment.requestor;
var requestLib			= environment.requestLib;
var titleDescriptor	= environment.titleDescriptor;

log_debug('circ_permit_hold: permit circ on ' +
	' Copy: '					+ copy.id + 
	', Patron:'					+ patron.id +
	', Patron Username:'		+ patron.usrname +
	', Patron Library: '		+ patron.home_ou.name +
	', Copy location: '		+ copy.location.name +
	', Item Type: '			+ titleDescriptor.item_type +
	', Item Form: '			+ titleDescriptor.item_form +
	', Item Lang: '			+ titleDescriptor.item_lang +
	', Item Audience: '		+ titleDescriptor.audience +
	'');





if( titleDescriptor.item_type == 'g'  /* projected medium */
	&& copy.circ_lib != patron.home_ou.id )
	return result.event = 'CIRC_EXCEEDS_COPY_RANGE';


return result.event = 'SUCCESS';


} go();


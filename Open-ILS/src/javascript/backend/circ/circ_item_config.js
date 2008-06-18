load_lib('circ/circ_lib.js');
log_debug('loading circ_item_config.js ...');


/* SIP media types
000 Other
001 Book
002 Magazine
003 Bound journal
004 Audio tape
005 Video tape
006 CD/CDROM
007 Diskette
008 Book with diskette
009 Book with CD
010 Book with audio tape
*/

/* ----------------------------------------------------------------------------- 
	Configure the duration rules for the various item types and circ modifiers
	MARC Fixed Field info:
	http://www.oclc.org/bibformats/en/fixedfield/
	----------------------------------------------------------------------------- */

var MARC_ITEM_TYPE_MAP = {
	a : { /* Language material [Books] */
		SIPMediaType			: '001',
		magneticMedia			: 'f',
		durationRule			: 'default',
		recurringFinesRule	    : 'default',
		maxFine					: 'default'
	},
    /* add more MARC item type configs as needed... */
}

/* make 't' and 'a' share the same config info */
MARC_ITEM_TYPE_MAP.t = MARC_ITEM_TYPE_MAP.a;


var CIRC_MOD_MAP = {
	'bestseller'				: {
		SIPMediaType			: '001',
		magneticMedia			: 'f',
		durationRule			: 'default',
		recurringFinesRule	    : 'default',
		maxFine					: 'default'
	},
}


/* this will set defaults even if no one asked for them */
log_debug("Calling getItemConfig() to force defaults..");
result.item_config = getItemConfig();


function getItemConfig() {

	var config = null;
	var marcType	= getMARCItemType();
	var circMod		= copy.circ_modifier;

    if( circMod ) {
        config = CIRC_MOD_MAP[circMod];
        if(!config) 
            config = CIRC_MOD_MAP[circMod.toLowerCase()]
    }

    if(!config)
		config = MARC_ITEM_TYPE_MAP[marcType];

    if(!config) {
        config = {};
		config.SIPMediaType = '001';
		config.magneticMedia = 'f';
		config.durationRule	= 'default';
		config.recurringFinesRule = 'default';
		config.maxFine = 'default';
    }

    return config
}






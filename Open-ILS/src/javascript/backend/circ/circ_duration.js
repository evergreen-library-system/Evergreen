function go(){

load_lib('circ/circ_lib.js');
log_vars('circ_duration');

/* ----------------------------------------------------------------------------- 
	Configure the duration rules for the various item types and circ modifiers

	MARC Fixed Field info:
	http://www.oclc.org/bibformats/en/fixedfield/

	----------------------------------------------------------------------------- */




var MARC_ITEM_TYPE_MAP = {

	a : { /* Language material [Books] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	t : { /* Manuscript language material [Books] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	g : { /* Projected medium [Videos, etc.] */
		durationRule			: '7_days_0_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	k : { /* Two-dimensional nonprojectable graphic [Card, charts, etc.] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	r : { /* Three-dimensional artifact or naturally occurring object [Models, games, etc.] */ 
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	o : { /* Kit [Mixture of item types] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	p : { /* Mixed materials [Mixture of item types] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	e : { /* Cartographic material [Map] */
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	f : { /* Manuscript cartographic material [Map] */
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	c : { /* Notated music [Printed music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	d : { /* Manuscript notated music [Printed music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	i : { /* Nonmusical sound recording [Audiobooks, sound effects, etc.] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	j : { /* Musical sound recording [Music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	m : { /* Computer file */
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	}
}


var CIRC_MOD_MAP = {

	'Atlas'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Bestseller (high demand)'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Bestseller not high demand'	: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Bestseller-not holdable'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesLevel	: 'normal',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'Compact Disc'						: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'DVD'									: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'DVD with long loan period'	: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Filmstrip'							: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Laserdisc'							: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Magazine-Circulating'			: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'New AV material'					: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'New Book'							: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Pamphlet'							: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Record'								: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Talkingbook'						: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Toy'									: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Video (high demand)'			: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'
	},

	'Video public performance'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		recurringFinesLevel	: 'normal',
		maxFine					: 'overdue_mid'

	}
}




/* Get the load duration level directly from the copy */
result.durationLevel	= copy.loan_duration;


/* ----------------------------------------------------------------------------- 
	If a circ_modifier is defined on the copy and we have config info for the
	provided circ_modifier, use that config.  Otherwise fall back on the MARC 
	item type
	----------------------------------------------------------------------------- */
var marcType	= getMARCItemType();
var circMod		= copy.circ_modifier;
var itemForm	= (marcXMLDoc) ? extractFixedField(marcXMLDoc,'Form') : "";


var config = 
	( circMod && CIRC_MOD_MAP[circMod] ) ?
	CIRC_MOD_MAP[circMod] : 
	MARC_ITEM_TYPE_MAP[marcType];


if( CIRC_MOD_MAP[circMod] ) 
	log_debug("a circ_mod config exists for the copy");

if( MARC_ITEM_TYPE_MAP[marcType] )
	log_debug("an item_type config exists for the copy");


log_debug("Copy circ modifier = " + circMod + " and item type = " + marcType );


/* ----------------------------------------------------------------------------- 
	Now set the rule values based on the config.  If there is no configured info
	on this copy, fall back on defaults.
	----------------------------------------------------------------------------- */
if( config ) {

	log_debug("circ_duration found a config for the copy");
	result.durationRule			= config.durationRule;
	result.recurringFinesRule	= config.recurringFinesRule;
	result.recurringFinesLevel = config.recurringFinesLevel;
	result.maxFine					= config.maxFine;

} else {

	result.durationRule			= '14_days_2_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.recurringFinesLevel = 'normal';
	result.maxFine					= "overdue_mid";
}




/* ----------------------------------------------------------------------------- 
	Add custom rules here.  
	----------------------------------------------------------------------------- */

/* statelib has some special circ rules */

if( isOrgDescendent('STATELIB', copy.circ_lib.id) ) {

	result.durationRule			= '35_days_1_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.recurringFinesLevel = 'normal';
	result.maxFine					= "overdue_mid";

	/* reference, microfiche, microfilm */
	if(	isTrue(copy.ref)	|| 
			itemForm == 'a'	|| 
			itemForm == 'b' ) {

		result.durationRule		= '14_days_2_renew';
	}	
}



} go();


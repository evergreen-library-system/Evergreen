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
		maxFine					: 'overdue_mid'
	},

	t : { /* Manuscript language material [Books] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	g : { /* Projected medium [Videos, etc.] */
		durationRule			: '7_days_0_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	k : { /* Two-dimensional nonprojectable graphic [Card, charts, etc.] */
		durationRule			: '3_month_0_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	r : { /* Three-dimensional artifact or naturally occurring object [Models, games, etc.] */ 
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	o : { /* Kit [Mixture of item types] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	p : { /* Mixed materials [Mixture of item types] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	e : { /* Cartographic material [Map] */
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	f : { /* Manuscript cartographic material [Map] */
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	c : { /* Notated music [Printed music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	d : { /* Manuscript notated music [Printed music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	i : { /* Nonmusical sound recording [Audiobooks, sound effects, etc.] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	j : { /* Musical sound recording [Music] */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	m : { /* Computer file */
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	}
}


var CIRC_MOD_MAP = {

	'art'		: {
		durationRule			: '3_month_0_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'atlas'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'audiobook' : {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'av' : {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'bestseller'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'bestsellernh'		: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'cd'				: {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'dvd'							: {
		durationRule			: '7_days_0_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'e-book' : {
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'equipment' : { 
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'filmstrip'					: {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'kit' : {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'magazine'	: {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'map' : {
		durationRule			: '3_days_1_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'microform' : {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'music' : {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'record'						: {
		durationRule			: '14_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'software' : {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '10_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'talking book'				: {  
		durationRule			: 'unlimited',
	},

	'toy'							: {
		durationRule			: '7_days_2_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},

	'video'	: {
		durationRule			: '7_days_0_renew',
		recurringFinesRule	: '50_cent_per_day',
		maxFine					: 'overdue_mid'
	},
}



/* treat pre-cat copies like vanilla books */
if( isTrue(isPrecat) ) {
	log_info("pre-cat copy getting duration defaults...");
	result.durationRule			= '14_days_2_renew';
	result.recurringFinesRule	= '10_cent_per_day';
	result.maxFine					= 'overdue_mid';
	return;
}


/* ----------------------------------------------------------------------------------- 
	If a circ_modifier is defined on the copy and we have config info for the
	provided circ_modifier, use that config.  Otherwise fall back on the MARC item type
	----------------------------------------------------------------------------------- */
var marcType	= getMARCItemType();
var circMod		= copy.circ_modifier;
var itemForm	= (marcXMLDoc) ? extractFixedField(marcXMLDoc,'Form') : "";


var config;

if( CIRC_MOD_MAP[circMod] ) {
	/* if we have a config for the given circ_modifier, use it */
	log_debug("a circ_mod config exists for the copy");
	config = CIRC_MOD_MAP[circMod];

} else {
	/* otherwise, fall back on the MARC item type */
	config = MARC_ITEM_TYPE_MAP[marcType];
}



/* ----------------------------------------------------------------------------- 
	Now set the rule values based on the config.  If there is no configured info
	on this copy, fall back on defaults.
	----------------------------------------------------------------------------- */
if( config ) {

	log_debug("circ_duration found a config for the copy");
	result.durationRule			= config.durationRule;
	result.recurringFinesRule	= config.recurringFinesRule;
	result.maxFine					= config.maxFine;

	log_debug(config.durationRule + ' : ' + config.recurringFinesRule + ' : ' + config.maxFine );

} else {

	result.durationRule			= '14_days_2_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.maxFine					= "overdue_mid";
}




/* ----------------------------------------------------------------------------- 
	Add custom rules here.  
	----------------------------------------------------------------------------- */

/* statelib has some special circ rules */

if( isOrgDescendent('STATELIB', copy.circ_lib.id) ) {

	result.durationRule			= '35_days_1_renew';
	result.recurringFinesRule	= "10_cent_per_day";
	result.maxFine					= "overdue_mid";

	/* reference, microfiche, microfilm */
	if(	isTrue(copy.ref)	|| 
			itemForm == 'a'	|| 
			itemForm == 'b' ) {

		result.durationRule		= '14_days_2_renew';
	}	
}



} go();



var cgi					= null;
var patron				= null;
var advanced			= false;
var SC_FETCH_ALL     = 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
var FETCH_ID_TYPES	= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
var FETCH_GROUPS		= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
var identTypes			= null;
var groupTree			= null;
var ERRORS				= ""; /* global set of errors */

var myPerms		= [ 'CREATE_USER', 'UPDATE_USER', 'CREATE_PATRON_STAT_CAT_ENTRY_MAP' ];

var pages		= [ 
	'uedit_userid', 
	'uedit_contact_info', 
	'uedit_addresses', 
	'uedit_groups', 
	'uedit_stat_cats', 
	'uedit_surveys',
	'uedit_finalize',
	];

/* ID's of objects that should be focused when their page is made visible */
var pageFocus	= [
	'ue_barcode',
	'ue_email1',
	'ue_addr_label',
	'ue_profile',
	'ue_stat_cat_selector_1',
	'ue_survey_selector_1',
	'ue_view_summary'
];

var regexes		= {};
regexes.phone	= /\d{3}-\d{3}-\d{4}/;
regexes.email	= /\w+\@\w+\.\w+/;
regexes.date	= /^\d{4}-\d{2}-\d{2}/;
regexes.isnum	= /^\d+$/;

/* fetch the necessary data to start off */
function uEditInit() {

	cgi		= new CGI();
	session	= cgi.param('ses');
	if(cgi.param('adv')) advanced = true 
	if(!session) throw "User session is not defined";

	fetchUser(session);
	$('uedit_user').appendChild(text(USER.usrname()));
	uEditShowPage('uedit_userid');

	setTimeout( 
		function() { 
			fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
			uEditDrawUser(fetchFleshedUser(cgi.param('usr')));
			uEditBuildLibSelector();
			uEditFetchIDTypes();
			uEditFetchGroups();
			uEditFetchStatCats();
			uEditFetchSurveys();
		}, 20 
	);
}

function uEditNext() {
	var i = _findActive();
	if( i < (pages.length - 1)) uEditShowPage(pages[i+1]);
}

function uEditPrev() {
	var i = _findActive();
	if( i > 0 ) uEditShowPage(pages[i-1]);
}


function uEditShowPage(id) {
	if( id == null ) return;

	for( var p in pages ) {
		var page = pages[p];
		hideMe($(page));
		removeCSSClass($(page+'_label'), 'label_active');
	}

	unHideMe($(id));
	addCSSClass($(id+'_label'), 'label_active');
	var idx = _findPageIdx(id);
	var fpage = pageFocus[idx];
	if(fpage) { $(fpage).focus(); try{$(fpage).select()}catch(e){} }

	unHideMe($('ue_back'));
	unHideMe($('ue_fwd'));

	if(idx == 0) hideMe($('ue_back'));
	if(idx == (pages.length-1)) hideMe($('ue_fwd'));
}


function _findActive() {
	for( var p in pages ) {
		if(! $(pages[p]).className.match(/hide_me/) )
			return parseInt(p);
	}
	return null;
}
function _findPageIdx(name) {
	for( var i in pages ) {
		var page = pages[i];
		if( page == name ) return i;
	}
	return -1;
}

function uEditAddrHighlight( node, type ) {
	var tbody = $('ue_address_tbody');
	for( var c in tbody.childNodes ) {
		var row = tbody.childNodes[c];
		if(row.nodeType != XML_ELEMENT_NODE ) continue;
		var div = $n(row,'ue_addr_'+type+'_yes').parentNode;
		removeCSSClass(div, 'addr_info_checked');
	}
	addCSSClass(node.parentNode, 'addr_info_checked');
}



function uEditDrawUser(patron) {
	if(!patron) return 0;
}

function uEditFetchIDTypes() {
	var req = new Request(FETCH_ID_TYPES);
	req.callback(uEditDrawIDTypes);
	req.send();
}

function uEditDrawIDTypes(r) {

	var types = r.getResultObject();
	var pri_sel = $('ue_primary_ident_type');
	var sec_sel = $('ue_secondary_ident_type');

	var idx = 1;
	for( var t in types ) {
		var type = types[t];
		setSelectorVal( pri_sel, idx, type.name(), type.id() );
		setSelectorVal( sec_sel, idx++, type.name(), type.id() );
	}
	identTypes = types;
}

function uEditFetchStatCats() {
	var req = new Request(SC_FETCH_ALL, SESSION);
	req.callback(uEditDrawStatCats);
	req.send();
}

function uEditDrawStatCats(r) {
	var cats = r.getResultObject();
	var tbody = $('ue_stat_cat_tbody');
	var templ = tbody.removeChild($('ue_stat_cat_row'));

	for( var c in cats ) {
		var row = templ.cloneNode(true);
		uEditInsertCat( tbody, row, cats[c], c );
		tbody.appendChild(row);
	}
}

function uEditInsertCat( tbody, row, cat, idx ) {

	cat.entries().sort(  /* sort the entries by value */
		function( a, b ) { 
			if( a.value().toLowerCase() > b.value().toLowerCase()) return 1;
			if( a.value().toLowerCase() < b.value().toLowerCase()) return -1;
			return 0;
		}
	);

	var selector = $n(row, 'ue_stat_cat_selector');
	if( idx == 0 ) selector.id = 'ue_stat_cat_selector_1'; 
	$n(row, 'ue_stat_cat_name').appendChild(text(cat.name()));
	$n(row, 'ue_stat_cat_owner').appendChild(text(fetchOrgUnit(cat.owner()).shortname()));

	var idx = 1;
	for( var e in cat.entries() ) {
		var entry = cat.entries()[e];
		setSelectorVal( selector, idx++, entry.value(), entry.id() );
	}
}

function uEditFetchSurveys() {
	var req = new Request(SV_FETCH_ALL, SESSION);
	req.callback(uEditDrawSurveys);
	req.send();
}

function uEditDrawSurveys(r) {

	var surveys = r.getResultObject();
	var div = $('uedit_surveys');
	var table = div.removeChild($('ue_survey_table'));

	var x = 0;
	for( var s in surveys ) {
		var survey = surveys[s];
		var clone = table.cloneNode(true);
		uEditInsertSurvey( div, clone, survey, x++ );
		div.appendChild(clone);
	}
}

function uEditInsertSurvey( div, table, survey, sidx ) {
	$n(table, 'ue_survey_name').appendChild(text(survey.name()));
	$n(table, 'ue_survey_desc').appendChild(text(survey.description()));
	var tbody = $n(table, 'ue_survey_tbody');
	var templ = tbody.removeChild($n(table, 'ue_survey_row'));

	var polldiv		= $('ue_survey_answer_poll');

	var idx = 1;
	for( var q in survey.questions() ) {
		var row = templ.cloneNode(true);
		uEditInsertSurveyQuestion( div, table, tbody, row, survey, survey.questions()[q], sidx );
		tbody.appendChild(row);
	}
}

function uEditInsertSurveyQuestion( div, table, tbody, row, survey, question, sidx ) {

	$n(row, 'ue_survey_question').appendChild(text(question.question()));

	var selector	= $n(row, 'ue_survey_answer');
	var polldiv		= $n(row, 'ue_survey_answer_poll');
	var idx			= 1;
	var polltbody	= $n(row, 'ue_survey_answer_poll_tbody');
	var pollrow		= polltbody.removeChild($n(polltbody, 'ue_survey_answer_poll_row'));

	if( sidx == 0 ) selector.id = 'ue_survey_selector_1'; 

	for( var a in question.answers() ) {

		var answer = question.answers()[a];

		if( survey.poll() ) {

			unHideMe(polldiv);
			var prow = pollrow.cloneNode(true);
			$n(prow, 'ue_survey_answer_poll_answer').appendChild(text(answer.answer()));

			$n(prow, 'ue_survey_answer_poll_radio').appendChild(
				elem('input', { 
					type	: 'radio', 
					name	: 'survey_poll_answer_'+survey.id(),
					id		:  answer.id()
				}));

			polltbody.appendChild(prow);

		} else {

			unHideMe(selector.parentNode);
			setSelectorVal( selector, idx++, answer.answer(), answer.id() );
		}
	}
}


function uEditFetchError(id) { if($(id)) return $(id).innerHTML + "\n"; return "";}


function uEditSaveUser() {

	var card		= null;

	if(patron == null) { 
		patron = new au(); 
		patron.isnew(1);
		card = new ac();
		patron.card(-1); /* attach to the virtual id of the card */
		patron.cards([card]);

	} else { 
		patron.ischanged(1); 
		patron.isnew(0);
	}

	uEditFleshCard(card);
	uEditAddBasicPatronInfo(patron);
	uEditAddPhones(patron);
	uEditAddIdents(patron);
	uEditAddGroupsAndPerms(patron);

	if(ERRORS) { alert(ERRORS); ERRORS = ""; }
	else alert(js2JSON(patron));
}

/* returns true if an error occurred */
function uEditSetVal( obj, func, val, regxtype, errtype ) {

	var error = uEditFetchError(errtype);
	var iserr = false;

	while(1) {

		if( val == null ) { iserr = true; break; }

		if(!instanceOf(val, String)) {
			try { val = val.value; } catch(e) { return; }
		}

		if(val == "" ) { iserr = true; break; }

		if(regxtype && regexes[regxtype] 
			&& !val.match(regexes[regxtype]) ) { iserr = true; break; }

		try { obj[func](val); } catch(e) {
			alert("Error running function: " +func);
		}

		break;
	}

	if(iserr) { ERRORS += error; return true; }
	return false;
}


function uEditAddBasicPatronInfo(patron) {



	/* make sure passwords match */
	var p1 = $('ue_password1').value;
	var p2 = $('ue_password1').value;
	if( p1 != p2 || uEditSetVal( patron, "passwd", p1 )) 
		ERRORS += uEditFetchError('ue_bad_password');

	uEditSetVal(patron, "usrname", $('ue_username'), null, 'ue_bad_username' );
	uEditSetVal(patron, "first_given_name", $('ue_firstname'), null, 'ue_bad_firstname' );
	uEditSetVal(patron, "second_given_name", $('ue_middlename'), null, 'ue_bad_middlename' ); 
	uEditSetVal(patron, "family_name", $('ue_lastname'), null, 'ue_bad_lastname' ); 
	uEditSetVal(patron, "dob", $('ue_dob'), 'date', 'ue_bad_dob' );

	patron.suffix($('ue_suffix').value); /* suffis isn't required */


	/* make sure emails match */
	var email	= $('ue_email1').value;
	var email2	= $('ue_email2').value;
	if( email != email2 || uEditSetVal(patron, "email", email, 'email' ))
		ERRORS += uEditFetchError('ue_bad_email');

	patron.home_ou(getSelectorVal($('ue_org_selector')));
}

function uEditAddPhones(patron) {


	/* verifies the phone numbers are formatted correctly */
	var verify = function(n1, n2, n3) {
		var a = n1.value;
		var p = n2.value;
		var s = n3.value;
		if( !a || !p || !s ) return false;
		return a + '-' + p + '-' + s;
	}


	var er = 'ue_bad_phone'

	uEditSetVal( patron, "day_phone", 
		verify($('ue_day_phone_area'), 
		$('ue_day_phone_prefix'), 
		$('ue_day_phone_suffix')), 'phone', er );

	uEditSetVal( patron, "evening_phone", 
		verify($('ue_night_phone_area'), 
		$('ue_night_phone_prefix'), 
		$('ue_night_phone_suffix')), 'phone', er );

	uEditSetVal( patron, "other_phone", 
		verify($('ue_other_phone_area'), 
		$('ue_other_phone_prefix'), 
		$('ue_other_phone_suffix')), 'phone', er );

}

function uEditFleshCard(card) {
	if(!card) return "";

	if(uEditSetVal( card, "barcode", $('ue_barcode'), null, 'ue_bad_barcode' ))
		return;	

	card.id(-1);
	card.active(1);
	return "";
}

function uEditAddIdents(patron) {

	var err = 'ue_no_ident';

	uEditSetVal( patron, "ident_type", 
		getSelectorVal($('ue_primary_ident_type')), 'isnum', err );

	uEditSetVal( patron, "ident_type2", 
		getSelectorVal($('ue_secondary_ident_type')), 'isnum', err );

	uEditSetVal( patron, "ident_value", 
		$('ue_primary_ident'), null, err );

	uEditSetVal( patron, "ident_value2", 
		$('ue_secondary_ident'), null, err );

}


function uEditBuildLibSelector( node, depth, selector ) {
	if(!selector) selector = $('ue_org_selector');
	if(!node) { depth = 0; node = globalOrgTree; }
	
	var opt = insertSelectorVal( selector, -1, node.name(), node.id(), null, depth++ );

	/* allow these orgs to be selectable via permission? */
	if(!findOrgType(node.ou_type()).can_have_vols()) opt.disabled = true; 

	if( node.id() == USER.home_ou() ) setSelector(selector, node.id());
	for( var c in node.children() ) 
		uEditBuildLibSelector(node.children()[c], depth, selector);
}

function uEditFetchGroups() {
	var req = new Request(FETCH_GROUPS);
	req.callback(uEditDrawGroups);
	req.send();
}

function uEditDrawGroups(r, tree, depth, selector) {

	if(!tree) {
		tree = r.getResultObject();	
		depth = 0;
		groupTree = tree;
		selector = $('ue_profile');
	}

	insertSelectorVal( selector, -1, tree.name(), tree.id(), null, depth++ );	
	for( var c in tree.children() ) 
		uEditDrawGroups( null, tree.children()[c], depth, selector );
}



function uEditAddGroupsAndPerms(patron) {

	uEditSetVal( patron, "profile", 
		getSelectorVal($('ue_profile')), 'isnum', 'ue_no_profile');

	var expire = $('ue_expire').value;
	if(expire) 
		uEditSetVal( patron, "expire_date", expire, 'date', 'ue_bad_expire' );

	if($('ue_active').checked) patron.active(1);
	if($('ue_barred').checked) patron.barred(1);
	if($('ue_group_lead').checked) patron.master_account(1);

	uEditSetVal( patron, "claims_returned_count", 
		$('ue_claims_returned'), 'isnum', 'ue_bad_claims_returned');
}




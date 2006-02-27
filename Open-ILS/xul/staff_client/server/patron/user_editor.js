
var cgi							= null;
var patron						= null;
var advanced					= false;
var SC_FETCH_ALL				= 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP				= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL				= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
var FETCH_ID_TYPES			= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
var FETCH_GROUPS				= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
var UPDATE_PATRON				= 'open-ils.actor:open-ils.actor.patron.update';
var identTypes					= {};
var groupTree					= null;
var cachedSurveys				= {};
var cachedSurveyQuestions	= {};
var cachedSurveyAnswers		= {};
var ERRORS						= ""; /* global set of errors */
var cachedStatCats			= {};
var deletedStatCats			= {};
var cachedAddresses			= {};
var deletedAddresses			= {};

/* if they don't have these perms, they shouldn't be here */
//var myPerms = [ 'CREATE_USER', 'UPDATE_USER', 'CREATE_PATRON_STAT_CAT_ENTRY_MAP' ];

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
	'ue_addr_label_1',
	'ue_profile',
	'ue_stat_cat_selector_1',
	'ue_survey_selector_1',
	'ue_view_summary'
];

var regexes		= {};
regexes.phone	= /\d{3}-\d{3}-\d{4}/;
regexes.email	= /.+\@.+\..+/;
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

			/* these can be asynch */
			/*fetchHighestPermOrgs( SESSION, USER.id(), myPerms );*/
			uEditFetchSurveys();

			/* these have to be synchronous */
			uEditBuildLibSelector();
			uEditFetchIDTypes();
			uEditBuildAddrs();
			uEditFetchGroups();
			uEditFetchStatCats();

			uEditDrawUser(fetchFleshedUser(cgi.param('usr')));

		}, 20 
	);
}

/* UI code ---------------------------------------------------- */

function uEditNext() {
	var i = _findActive();
	if( i < (pages.length - 1)) uEditShowPage(pages[i+1]);
}

function uEditPrev() {
	var i = _findActive();
	if( i > 0 ) uEditShowPage(pages[i-1]);
}

function uEditFetchError(id) { if($(id)) return $(id).innerHTML + "\n"; return "";}

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


/* ------------------------------------------------------------------------------ */
/* Fetch code
/* ------------------------------------------------------------------------------ */
function uEditFetchIDTypes() {
	var req = new Request(FETCH_ID_TYPES);
	//req.callback(uEditDrawIDTypes);
	req.send(true);
	uEditDrawIDTypes(req.request);
}

function uEditFetchStatCats() {
	var req = new Request(SC_FETCH_ALL, SESSION);
	//req.callback(uEditDrawStatCats);
	req.send(true);
	uEditDrawStatCats(req.request);
}

function uEditFetchSurveys() {
	var req = new Request(SV_FETCH_ALL, SESSION);
	req.callback(uEditDrawSurveys);
	req.send();
}


/* ------------------------------------------------------------------------------ */
/* Save the user
/* ------------------------------------------------------------------------------ */
var uEditExistingStatEntries;
var uEditExistingSurveyResponses;

function uEditSaveUser() {
	uEditCollectData();

	if(ERRORS) { 
		alert(ERRORS); 
		ERRORS = ""; 
		return;
	}

	//alert(js2JSON(patron));
	//return;

	var req = new Request(UPDATE_PATRON, SESSION, patron);
	req.send(true);
	var result = req.result();
	if( checkILSEvent(result) ) alert(js2JSON(result));
	else alert($('ue_success').innerHTML);

}

function uEditCollectData() {

	var card	= null;

	if(patron == null) { 
		patron = new au(); 
		patron.isnew(1);
		patron.id(-1);
		card = new ac();
		patron.card(-1); /* attach to the virtual id of the card */
		patron.cards([card]);

	} else { 

		/* if this function is called again, patron will exist */
		if(!patron.isnew()) { 
			patron.ischanged(1); 
			patron.isnew(0);
			if(!uEditExistingStatEntries)
				uEditExistingStatEntries = patron.stat_cat_entries();
			if(!uEditExistingSurveyResponses)
				uEditExistingSurveyResponses = patron.survey_responses();
		}
	}

	patron.stat_cat_entries([]);
	patron.survey_responses([]);

	uEditFleshCard(card);
	uEditAddBasicPatronInfo(patron);
	uEditAddPhones(patron);
	uEditAddIdents(patron);
	uEditAddAddresses(patron);
	uEditAddGroupsAndPerms(patron);
	uEditReapStatCats(patron);
	uEditReapSurveys(patron);

}



/* ------------------------------------------------------------------------------ */
/* Draw the user
/* ------------------------------------------------------------------------------ */
function uEditDrawUser(p) {

	hideMe($('uedit_loading'));
	unHideMe($('ue_maintd'));

	if(!p) return;
	patron = p;

	$('ue_barcode').value			= patron.card().barcode();
	$('ue_username').value			= patron.usrname();
	$('ue_firstname').value			= patron.first_given_name();
	$('ue_middlename').value		= patron.second_given_name();
	$('ue_lastname').value			= patron.family_name();
	$('ue_suffix').value				= patron.suffix();
	$('ue_dob').value					= patron.dob();
	$('ue_primary_ident').value	= patron.ident_value();
	$('ue_secondary_ident').value	= patron.ident_value2();
	$('ue_email1').value				= patron.email();
	$('ue_email2').value				= patron.email();
	$('ue_expire').value				= patron.expire_date();
	$('ue_active').value				= patron.active();
	$('ue_barred').value				= patron.barred();
	$('ue_claims_returned').value	= patron.claims_returned_count();
	$('ue_alert_message').value	= patron.alert_message();

	setSelector( $('ue_primary_ident_type'), patron.ident_type() );
	setSelector( $('ue_secondary_ident_type'), patron.ident_type2() );
	setSelector( $('ue_org_selector'), patron.home_ou() );
	setSelector( $('ue_profile'), patron.profile() );
	
	/* flesh out the phone numbers ------------------------- */
	var dp = patron.day_phone();
	var np = patron.evening_phone();
	var op = patron.other_phone();

	if(dp) {
		var daynums = dp.split('-');
		$('ue_day_phone_area').value		= daynums[0];
		$('ue_day_phone_prefix').value	= daynums[1];
		$('ue_day_phone_suffix').value	= daynums[2];
	}

	if(np) {
		var nightnums = np.split('-');
		$('ue_night_phone_area').value	= nightnums[0];
		$('ue_night_phone_prefix').value	= nightnums[1];
		$('ue_night_phone_suffix').value	= nightnums[2];
	}

	if(op) {
		var othernums = op.split('-');
		$('ue_other_phone_area').value	= othernums[0];
		$('ue_other_phone_prefix').value	= othernums[1];
		$('ue_other_phone_suffix').value	= othernums[2];
	}


	/* Flesh the addresses ------------------------------------ */
	var i = 0;
	var tbody = $('ue_address_tbody');	
	for( var i = 0; i != patron.addresses().length; i++ ) {
		var addr = patron.addresses()[i];
		cachedAddresses[addr.id()] = addr;
		var row;
		if( i == 0 ) row = getElementsByTagNameFlat(tbody, 'tr')[0];
		else row = $('ue_address_new').onclick(); /* create a new row if necessary */

		row.setAttribute('exists', addr.id() );

		if( patron.mailing_address().id() == addr.id())
			$n(row, 'ue_addr_mailing_yes').checked = true;

		if( patron.billing_address().id() == addr.id())
			$n(row, 'ue_addr_billing_yes').checked = true;
		
		if( addr.valid() ) $n(row, 'ue_addr_valid_yes').checked = true;

	
		$n(row, 'ue_addr_label').value	= addr.address_type();
		$n(row, 'ue_addr_street1').value	= addr.street1();
		$n(row, 'ue_addr_street2').value = addr.street2();
		$n(row, 'ue_addr_city').value		= addr.city();
		$n(row, 'ue_addr_county').value	= addr.county();
		$n(row, 'ue_addr_state').value	= addr.state();
		$n(row, 'ue_addr_zip').value		= addr.post_code();
		$n(row, 'ue_addr_country').value	= addr.country();

	}



	var stattbody = $('ue_stat_cat_tbody');
	for( var m in patron.stat_cat_entries() ) {
		var map = patron.stat_cat_entries()[m];
		var row = grep( getElementsByTagNameFlat( stattbody, 'tr' ), 
			function(a) { return a.getAttribute('statcat') == map.stat_cat() })[0];
		$n(row, 'ue_stat_cat_newval').value = map.stat_cat_entry();
		setSelectorByName( $n(row, 'ue_stat_cat_selector'), map.stat_cat_entry() );
	}
}





/* ------------------------------------------------------------------------------ */
/* Draw the ID types
/* ------------------------------------------------------------------------------ */
function uEditDrawIDTypes(r) {

	var types	= r.getResultObject();
	var pri_sel = $('ue_primary_ident_type');
	var sec_sel = $('ue_secondary_ident_type');

	var idx = 1;
	for( var t in types ) {
		var type = types[t];
		identTypes[type.id()] = type;
		setSelectorVal( pri_sel, idx, type.name(), type.id() );

		if(patron && patron.ident_type() != null ) 
			setSelector( pri_sel, patron.ident_type() );

		setSelectorVal( sec_sel, idx++, type.name(), type.id() );
		if(patron && patron.ident_type2() != null ) 
			setSelector( sec_sel, patron.ident_type2() );
	}
}



/* ------------------------------------------------------------------------------ */
/* Stat Cat handling code
/* ------------------------------------------------------------------------------ */
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

/* fleshes the stat cat with entries in the dropdown */
function uEditInsertCat( tbody, row, cat, idx ) {

	cat.entries().sort(  /* sort the entries by value */
		function( a, b ) { 
			if( a.value().toLowerCase() > b.value().toLowerCase()) return 1;
			if( a.value().toLowerCase() < b.value().toLowerCase()) return -1;
			return 0;
		}
	);

	cachedStatCats[cat.id()] = cat;

	row.setAttribute('statcat', cat.id());
	var newval = $n(row, 'ue_stat_cat_newval');
	newval.onchange = function(){ 
		findParentByNodeName(newval,'tr').setAttribute('changed', '1'); }

	var selector = $n(row, 'ue_stat_cat_selector');
	selector.onchange = function(){ 
		findParentByNodeName(selector, 'tr').setAttribute('changed', '1'); 
		newval.value = getSelectorName(selector);
		newval.setAttribute('entry', getSelectorVal(selector));
	}

	if( idx == 0 ) selector.id = 'ue_stat_cat_selector_1'; 

	$n(row, 'ue_stat_cat_name').appendChild(text(cat.name()));
	$n(row, 'ue_stat_cat_owner').appendChild(
		text(fetchOrgUnit(cat.owner()).shortname()));

	var idx = 1;
	for( var e in cat.entries() ) {
		var entry = cat.entries()[e];
		setSelectorVal( selector, idx++, entry.value(), entry.id() );
	}
}

/* finds all the changed/new stat entries and updates the patron object*/
function uEditReapStatCats(patron) {
   var tbody = $('ue_stat_cat_tbody');
	for( var r in tbody.childNodes ) {
		var row = tbody.childNodes[r];
		if( !row || row.nodeName != 'tr' ) continue;
		if( row.getAttribute('changed') ) {
			var val = $n( row, 'ue_stat_cat_newval' );
			uEditCreateStatMap( patron, row.getAttribute('statcat'), 
				val.value, val.getAttribute('entry') );
		}
	}
}


function uEditCreateStatMap( patron, catid, newval, entryid ) {

	if( ! patron.isnew() ) {

		/* if the patron exists and we're editing an entry that's 
		already been created for this user... */
		for( var m in uEditExistingStatEntries ) {
			var map = uEditExistingStatEntries[m];
			if( map.stat_cat() == catid ) {
				if( newval ) map.ischanged(1);
				else map.isdeleted(1); 
				patron.stat_cat_entries().push(map);
				return;
			}
		}
	}

	var map = new actscecm();
	map.isnew(1);
	map.stat_cat_entry(newval);
	map.stat_cat(catid);
	map.target_usr(patron.id());
	patron.stat_cat_entries().push(map);
}



/* ------------------------------------------------------------------------------ */
/* Survey handling code
/* ------------------------------------------------------------------------------ */
function uEditDrawSurveys(r) {

	var surveys = r.getResultObject();
	var div = $('uedit_surveys');
	var table = div.removeChild($('ue_survey_table'));

	var x = 0;
	for( var s in surveys ) {
		var survey = surveys[s];
		cachedSurveys[survey.id()] = survey;
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
		var quest = survey.questions()[q];
		cachedSurveyQuestions[quest.id()] = quest;
		uEditInsertSurveyQuestion( div, table, tbody, row, survey, quest, sidx );
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

	table.setAttribute('survey', survey.id());
	row.setAttribute('question', question.id());

	selector.onchange = function() {
		row.setAttribute('answer', getSelectorVal(selector));
		row.setAttribute('changed', '1');
	}

	if( sidx == 0 ) selector.id = 'ue_survey_selector_1'; 

	for( var a in question.answers() ) {

		var answer = question.answers()[a];
		cachedSurveyAnswers[answer.id()] = answer;

		if( survey.poll() ) {

			unHideMe(polldiv);
			var prow = pollrow.cloneNode(true);


			$n(prow, 'ue_survey_answer_poll_answer').appendChild(text(answer.answer()));


			var input = elem('input', { 
					type	: 'radio', 
					name	: 'survey_poll_answer_'+survey.id(),
					id		:  answer.id()
				});

			input.onchange	= function() {
				row.setAttribute('answer', answer.id());
				row.setAttribute('changed', '1');
			}

			$n(prow, 'ue_survey_answer_poll_radio').appendChild(input);
			polltbody.appendChild(prow);

		} else {

			unHideMe(selector.parentNode);
			setSelectorVal( selector, idx++, answer.answer(), answer.id() );
		}
	}
}


function uEditReapSurveys(patron) {

	var div = $('uedit_surveys');
	var tables = getElementsByTagNameFlat(div, 'table');

	for( var t in tables ) {

		var table		= tables[t];
		var survey		= cachedSurveys[table.getAttribute('survey')];
		var tbody		= getElementsByTagNameFlat( table, 'tbody' )[0];
		var rows			= getElementsByTagNameFlat( tbody, 'tr' );

		for( var r in rows ) {
			var row	= rows[r];
			if(!row.getAttribute('changed')) continue;

			var resp	= new asvr();
			resp.isnew(1);
			resp.survey(survey.id());
			resp.usr(patron.id());
			resp.question(row.getAttribute('question'));
			resp.answer(row.getAttribute('answer'));
			patron.survey_responses().push( resp );
		}
	}
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

	if( p1 || patron.isnew() ) { /* existing patrons will have a blank password */
		if( p1 != p2 || uEditSetVal( patron, "passwd", p1 )) 
			ERRORS += uEditFetchError('ue_bad_password');
	}
	
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

	if( $('ue_other_phone_prefix').value ) {
		uEditSetVal( patron, "other_phone", 
			verify($('ue_other_phone_area'), 
			$('ue_other_phone_prefix'), 
			$('ue_other_phone_suffix')), 'phone', er );
	}

}

function uEditFleshCard(card) {
	if(!card) return "";

	if(uEditSetVal( card, "barcode", $('ue_barcode'), null, 'ue_bad_barcode' ))
		return;	

	card.id(-1);
	card.active(1);
	card.isnew(1);
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
	//req.callback(uEditDrawGroups);
	req.send(true);
	uEditDrawGroups(req.request);
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

	if($('ue_alert_message').value) 
		uEditSetVal(patron, "alert_message", $('ue_alert_message'));
}



function uEditAddAddresses(patron) {
	var tbody = $('ue_address_tbody');	
	patron.addresses([]);

	/* shove the addresses living in the page into the patron */
	for( var r in tbody.childNodes ) {
		var row = tbody.childNodes[r];
		if(!(row && row.nodeName == 'tr')) continue;
		patron.addresses().push( uEditBuildAddress( patron, tbody, row ));	
	}
	for( var a in deletedAddresses ) {
		var addr = deletedAddresses[a];
		patron.addresses().push(addr);
	}
}

/* extracts a single address from the page */
var uEditVirtualAddrId = -1;
function uEditBuildAddress( patron, tbody, row ) {

	var addr = new aua();
	var id = row.getAttribute('exists');

	if(id) {
		addr.id(id)
		addr.ischanged(1);
		addr.isnew(0);
	} else {
		addr.id(uEditVirtualAddrId--);
		addr.isnew(1);
	}

	if($n(row, 'ue_addr_mailing_yes').checked) patron.mailing_address(addr.id());
	if($n(row, 'ue_addr_billing_yes').checked) patron.billing_address(addr.id());
	if($n(row, 'ue_addr_valid_yes').checked) addr.valid(1);
	if($n(row, 'ue_addr_street2').value) addr.street2($n(row, 'ue_addr_street2').value);

	uEditSetVal(addr, "address_type",	$n(row, 'ue_addr_label'),			null, 'ue_bad_addr_label' );
	uEditSetVal(addr, "street1",			$n(row, 'ue_addr_street1'),		null, 'ue_bad_addr_street' );
	uEditSetVal(addr, "city",				$n(row, 'ue_addr_city'),			null, 'ue_bad_addr_city' );
	uEditSetVal(addr, "county",			$n(row, 'ue_addr_county'),			null, 'ue_bad_addr_county' );
	uEditSetVal(addr, "state",				$n(row, 'ue_addr_state'),			null, 'ue_bad_addr_state' );
	uEditSetVal(addr, "post_code",		$n(row, 'ue_addr_zip'),				null, 'ue_bad_addr_zip' );
	uEditSetVal(addr, "country",			$n(row, 'ue_addr_country'),		null, 'ue_bad_addr_country' );

	return addr;
}

function uEditRemoveAddress(node) {
	if( confirm($("ue_delete_addr_warn").innerHTML) ) {
		var td      = node.parentNode.parentNode;
		var mytab   = td.parentNode.parentNode.parentNode;
		var row 		= mytab.parentNode.parentNode;
		if( row.getAttribute('exists') ) {
			var a =  cachedAddresses[row.getAttribute('exists')];
			a.isdeleted(1);
			deletedAddresses[a.id()] = a;
		}
		var tbody   = row.parentNode;
		tbody.removeChild(mytab.parentNode.parentNode);
	}

}


var uEditAddrTemplate;
var uEditOrigAddrRow;
function uEditBuildAddrs() {

	var tbody = $('ue_address_tbody');
	uEditAddrTemplate = tbody.removeChild($('ue_address_template'));

	$('ue_address_new').onclick = 
		function() { 
			/* we have to retain the mailing/billing radio input values */
			var rows = getElementsByTagNameFlat(tbody,'tr');
			var mailrow;
			var billrow;
			for( var r in rows ) {
				var row = rows[r];
				if($n(row,'ue_addr_mailing_yes').checked) mailrow = row;
				if($n(row,'ue_addr_billing_yes').checked) billrow = row;
			}
			var newrow = uEditAddrTemplate.cloneNode(true);
			tbody.appendChild(newrow); 
			$n(newrow, 'ue_addr_label').focus();
			if(mailrow) $n(mailrow,'ue_addr_mailing_yes').checked = true;
			if(billrow) $n(billrow,'ue_addr_billing_yes').checked = true;
			return newrow;
		}

	/* go ahead and add a blank addr */
	if(!patron) {
		var row = uEditAddrTemplate.cloneNode(true);
		uEditOrigAddrRow = row;
		$n( row, 'ue_addr_label').id = 'ue_addr_label_1';
		tbody.appendChild(row); 
		return;
	}
}


function uEditShowSummary() {
	uEditCollectData();
	var table = $('ue_summary_table').cloneNode(true);;
	uEditFleshSummaryTable(table);
	var win = window.open("", $('ue_summary_window').innerHTML );	
	win.document.body.innerHTML = "";
	win.document.body.appendChild(table);
	ERRORS = "";
}

function uEditFleshSummaryTable(table) {

	var yes = $('yes').innerHTML;
	var no = $('no').innerHTML;

	var identt1 = "";
	var identt2 = "";
	var homeorg = "";
	var profile	= "";

	if( patron.ident_type() != null) 
		identt1 = identTypes[patron.ident_type()].name();
	if( patron.ident_type2() != null ) 
		identt2 = identTypes[patron.ident_type2()].name();
	if( patron.home_ou() != null )
		homeorg = findOrgUnit(patron.home_ou()).name();
	if( patron.profile() != null )
		profile = findTreeItemById(groupTree, patron.profile()).name();


	$n(table, 'ue_summary_username').appendChild(text(patron.usrname()));
	$n(table, 'ue_summary_firstname').appendChild(text(patron.first_given_name()));
	$n(table, 'ue_summary_middlename').appendChild(text(patron.second_given_name()));
	$n(table, 'ue_summary_lastname').appendChild(text(patron.family_name()));
	$n(table, 'ue_summary_suffix').appendChild(text(patron.suffix()));
	$n(table, 'ue_summary_dob').appendChild(text(patron.dob()));
	$n(table, 'ue_summary_primary_ident_type').appendChild(text(identt1));
	$n(table, 'ue_summary_primary_ident').appendChild(text(patron.ident_value()));
	$n(table, 'ue_summary_secondary_ident_type').appendChild(text(identt2));
	$n(table, 'ue_summary_secondary_ident').appendChild(text(patron.ident_value2()));
	$n(table, 'ue_summary_email').appendChild(text(patron.email()));
	$n(table, 'ue_summary_dayphone').appendChild(text(patron.day_phone()));
	$n(table, 'ue_summary_nightphone').appendChild(text(patron.evening_phone()));
	$n(table, 'ue_summary_otherphone').appendChild(text(patron.other_phone()));
	$n(table, 'ue_summary_home_lib').appendChild(text(homeorg));
	$n(table, 'ue_summary_profile').appendChild(text(profile));
	$n(table, 'ue_summary_expire').appendChild(text(patron.expire_date()));
	$n(table, 'ue_summary_family_lead').appendChild(text( (patron.master_account()) ? yes : no ));
	$n(table, 'ue_summary_claims_returned').appendChild(text(patron.claims_returned_count()));
	$n(table, 'ue_summary_alert_message').appendChild(text(patron.alert_message()));

	uEditFleshSummaryAddresses( table, patron );
	uEditFleshSummaryStatCats( table, patron );
	uEditFleshSummarySurveys( table, patron );
	uEditFleshSummaryErrors( table );


}

function uEditFleshSummaryAddresses( table, patron ) {

	var addrtbody = $n(table, 'ue_summary_addr_tbody');
	var rowtmpl = addrtbody.removeChild($n(addrtbody, 'ue_summary_addr_row'));

	for( var a in patron.addresses() ) {
		var address = patron.addresses()[a];
		var row = rowtmpl.cloneNode(true);
		uEditFleshSummaryAddr( address, patron, row );
		addrtbody.appendChild(row);
		if(address.isdeleted()) addCSSClass(row, 'deleted');
	}
}


function uEditFleshSummaryAddr( address, patron, row ) {
	var yes = $('yes').innerHTML;
	var no = $('no').innerHTML;

	$n(row, 'label').appendChild(text(address.address_type()));
	$n(row, 'street1').appendChild(text(address.street1()));
	$n(row, 'street2').appendChild(text(address.street2()));
	$n(row, 'city').appendChild(text(address.city()));
	$n(row, 'county').appendChild(text(address.county()));
	$n(row, 'state').appendChild(text(address.state()));
	$n(row, 'country').appendChild(text(address.country()));
	$n(row, 'zip').appendChild(text(address.post_code()));
	$n(row, 'valid').appendChild(text( (address.valid()) ? yes : no ));

	$n(row, 'mailing').appendChild(text( 
		(patron.mailing_address() == address.id()) ? yes : no ));

	$n(row, 'billing').appendChild(text( 
		(patron.billing_address() == address.id()) ? yes : no ));
}


function uEditFleshSummaryStatCats( table, patron ) {
	var tbody = $n(table, 'ue_summary_stats_tbody');
	var rowtmpl = tbody.removeChild($n(tbody, 'ue_summary_stats_row'));

	for( var s in patron.stat_cat_entries() ) {
		row = rowtmpl.cloneNode(true);
		var entry = patron.stat_cat_entries()[s];
		var cat = cachedStatCats[entry.stat_cat()];
		$n(row, 'ue_summary_stat_name').appendChild(text(cat.name()));
		$n(row, 'ue_summary_stat_value').appendChild(text(entry.stat_cat_entry()));
		row.setAttribute('statcat', entry.stat_cat());
		if( entry.isdeleted() ) addCSSClass(row, 'deleted'); 
		tbody.appendChild(row);
	}

	for( var s in uEditExistingStatEntries ) {

		var entry = uEditExistingStatEntries[s]; 
		var rows = getElementsByTagNameFlat( tbody, 'tr' );
		var test = function(a) { return a.getAttribute('statcat') == entry.stat_cat() };

		if( ! grep( rows, test ) ) {

			row = rowtmpl.cloneNode(true);
			var cat = cachedStatCats[entry.stat_cat()];
			$n(row, 'ue_summary_stat_name').appendChild(text(cat.name()));
			$n(row, 'ue_summary_stat_value').appendChild(text(entry.stat_cat_entry()));
			row.setAttribute('statcat', entry.stat_cat());
			tbody.appendChild(row);
		}
	}


	if( ! getElementsByTagNameFlat( tbody, 'tr' )[1] )
		unHideMe($n(tbody, 'ue_summary_stat_cat_none'));
}


function uEditFleshSummarySurveys( table, patron ) {

	var tbody	= $n(table, 'ue_summary_survey_tbody');
	var rowtmpl = tbody.removeChild($n(tbody, 'ue_summary_survey_row'));

	for( var r in patron.survey_responses() ) {
		var row		= rowtmpl.cloneNode(rowtmpl);
		var resp		= patron.survey_responses()[r];
		var survey	= cachedSurveys[resp.survey()];
		var quest	= cachedSurveyQuestions[resp.question()];
		var answer	= cachedSurveyAnswers[resp.answer()];
		$n(row, 'ue_summary_survey_name').appendChild(text(survey.name()));
		$n(row, 'ue_summary_survey_question').appendChild(text(quest.question()));
		$n(row, 'ue_summary_survey_answer').appendChild(text(answer.answer()));
		tbody.appendChild(row);
	}

	if( ! getElementsByTagNameFlat(tbody, 'tr')[1])
		unHideMe($n(tbody, 'ue_summary_survey_none'))
}


function uEditFleshSummaryErrors( table ) {
	if(ERRORS) {
		unHideMe($n(table, 'ue_summary_errors_row'));
		var errors = ERRORS.replace(/\n/g, "<br/>");
		$n(table, 'ue_summary_errors').innerHTML += errors;
	}
}

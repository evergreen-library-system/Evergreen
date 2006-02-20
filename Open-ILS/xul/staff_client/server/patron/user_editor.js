
var cgi					= null;
var patron				= null;
var advanced			= false;
var SC_FETCH_ALL     = 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';

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


function uEditSaveUser() {

	if(patron == null) patron = new au();

	var barcode = $('ue_barcode').value;
	patron.usrname($('ue_username').value);	
	patron.passwd($('ue_password1').value);	
	patron.first_given_name($('ue_firstname').value);
	patron.second_given_name($('ue_middlename').value);
	patron.family_name($('ue_lastname').value);
	patron.suffix($('ue_suffix').value);
	patron.dob($('ue_dob').value);

	alert(js2JSON(patron));

}



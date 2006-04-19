/* -----------------------------------------------------------------------
	UI code for the user editor.  Handles breaking up the components
	into a wizard-like interface.
	----------------------------------------------------------------------- */


var pages = [ 
	'uedit_userid', 
	'uedit_contact_info', 
	'uedit_addresses', 
	'uedit_groups', 
	'uedit_stat_cats', 
	'uedit_surveys',
	'uedit_finalize',
	];

/* ID's of objects that should be focused when their page is made visible */
var pageFocus = [
	'ue_barcode',
	'ue_email',
	'ue_addr_label_1',
	'ue_profile',
	'ue_stat_cat_selector_1',
	'ue_survey_selector_1',
	'ue_view_summary'
];


function uEditNext() {
	/*
	if(uEditAlertErrors()) return;
	*/
	var i = _findActive();
	if( i < (pages.length - 1)) uEditShowPage(pages[i+1]);
}


function uEditPrev() {
	var i = _findActive();
	if( i > 0 ) uEditShowPage(pages[i-1]);
}

function uEditCheckErrors() {
	var errors = uEditGetErrorStrings();
	if(errors) unHideMe($('ue_errors'));
	else hideMe($('ue_errors'));
}

/*
function uEditFetchError(id) { if($(id)) return $(id).innerHTML + "\n"; return "";}
*/

function uEditShowPage(id) {
	if( id == null ) return;

	/*
	if(uEditAlertErrors()) return;
	*/

	for( var p in pages ) {
		var page = pages[p];
		hideMe($(page));
		removeCSSClass($(page+'_label'), 'label_active');
	}

	var idx = _findPageIdx(id);

	unHideMe($(id));
	addCSSClass($(id+'_label'), 'label_active');
	var fpage = pageFocus[idx];

	if($(fpage)) { 
		$(fpage).focus(); 
		try{$(fpage).select()}catch(e){} 
	}

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

/* ------------------------------------------------------------------------------ */
/* Below are the various UI components built from retrieved data */
/* ------------------------------------------------------------------------------ */


/* org selector */
function uEditBuildLibSelector( node, depth, selector ) {
	if(!selector) selector = $('ue_org_selector');
	if(!node) { depth = 0; node = globalOrgTree; }
	var opt = insertSelectorVal( 
		selector, -1, node.name(), node.id(), null, depth++ );
	if(!findOrgType(node.ou_type()).can_have_users()) opt.disabled = true; 
	if( node.id() == USER.ws_ou() ) 
		setSelector(selector, node.id());

	for( var c in node.children() ) 
		uEditBuildLibSelector(node.children()[c], depth, selector);
}


/* group tree selector */
function uEditDrawGroups(tree, depth, selector) {
	if(!selector) {
		selector = $('ue_profile');
		depth = 0;
	}
	groupsCache[tree.id()] = tree;
	insertSelectorVal( selector, -1, tree.name(), tree.id(), null, depth++ );	
	for( var c in tree.children() ) 
		uEditDrawGroups( tree.children()[c], depth, selector );
}


/* user identification types */
function uEditDrawIDTypes(types) {
	var pri_sel = $('ue_primary_ident_type');
	var sec_sel = $('ue_secondary_ident_type');
	var idx = 1;
	for( var t in types ) {
		var type = types[t];
		if(!type.name()) continue;
		identTypesCache[type.id()] = type;
		setSelectorVal( pri_sel, idx, type.name(), type.id() );
		setSelectorVal( sec_sel, idx++, type.name(), type.id() );
	}
}

/* user statistical catagories */
function uEditDrawStatCats(cats) {
	var tbody = $('ue_stat_cat_tbody');
	var templ = tbody.removeChild($('ue_stat_cat_row'));

	for( var c in cats ) {
		var row = templ.cloneNode(true);
		uEditInsertCat( row, cats[c], c );
		tbody.appendChild(row);
	}
}


function uEditInsertCat( row, cat, idx ) {

	cat.entries().sort(  /* sort the entries by value */
		function( a, b ) { 
			if( a.value().toLowerCase() > b.value().toLowerCase()) return 1;
			if( a.value().toLowerCase() < b.value().toLowerCase()) return -1;
			return 0;
		}
	);

	statCatsCache[cat.id()] = cat;

	/* register the new map object */
	uEditBuildSCMField(cat, row);

	var newval = $n(row, 'ue_stat_cat_newval');
	var selector = $n(row, 'ue_stat_cat_selector');

	selector.onchange = function() { 
		newval.value = getSelectorVal(selector);
		if(newval.onchange()) newval.onchange();
	}

	if( idx == 0 ) selector.id = 'ue_stat_cat_selector_1'; 

	$n(row, 'ue_stat_cat_name').appendChild(text(cat.name()));
	$n(row, 'ue_stat_cat_owner').appendChild(
		text(fetchOrgUnit(cat.owner()).shortname()));

	for( var e in cat.entries() ) {
		var entry = cat.entries()[e];
		setSelectorVal( selector, 
			(parseInt(e)+1), entry.value(), entry.value() );
	}
}

/* draw the surveys */
function uEditDrawSurveys(surveys) {
	var div = $('uedit_surveys');
	var table = div.removeChild($('ue_survey_table'));
	for( var s in surveys ) {
		var survey = surveys[s];
		surveysCache[survey.id()] = survey;
		var clone = table.cloneNode(true);
		uEditInsertSurvey( div, clone, survey, s );
		div.appendChild(clone);
	}
}

/* insert the servey then insert each of that surveys questions */
function uEditInsertSurvey( div, table, survey, sidx ) {
	$n(table, 'ue_survey_name').appendChild(text(survey.name()));
	$n(table, 'ue_survey_desc').appendChild(text(survey.description()));
	var tbody = $n(table, 'ue_survey_tbody');
	var templ = tbody.removeChild($n(table, 'ue_survey_row'));

	for( var q in survey.questions() ) {
		var row = templ.cloneNode(true);
		var quest = survey.questions()[q];
		uEditInsertSurveyQuestion( row, survey, quest );
		tbody.appendChild(row);
	}
}

function uEditInsertSurveyQuestion( row, survey, question ) {
	var selector = $n(row, 'ue_survey_answer');
	row.setAttribute('question', question.id());
	$n(row, 'ue_survey_question').appendChild(text(question.question()));
	for( var a in question.answers() ) {
		var answer = question.answers()[a];
		surveyAnswersCache[answer.id()] = answer;
		insertSelectorVal(selector, -1, answer.answer(), answer.id() );
	}

	surveyQuestionsCache[question.id()] = question;

	selector.onchange = function() {

		/* remove any existing responses for this survey */
		patron.survey_responses(
			grep( patron.survey_responses(),
				function(item) {
					return (item.survey() != survey.id());
				}
			)
		);

		if(!patron.survey_responses())
			patron.survey_responses([]);

		var val = getSelectorVal(selector);
		if(!val) return;

		var resp	= new asvr();
		resp.isnew(1);
		resp.survey(survey.id());
		resp.usr(patron.id());
		resp.question(row.getAttribute('question'));
		resp.answer(val);
		patron.survey_responses().push( resp );
	}
}





/* -----------------------------------------------------------------------
	Spit out the patron info to the summary display tables...
	----------------------------------------------------------------------- */

function uEditShowSummary() {
	hideMe($('main_div_container'));
	unHideMe($('summary_div_container'));

	for( var f in dataFields ) {

		var field = dataFields[f];
		if( field.object == patron ) {

			var val = uEditNodeVal(field);

			if(	field.key == 'profile'		||
					field.key == 'home_ou'		||
					field.key == 'ident_type'	||
					field.key == 'ident_type2') {

				val = getSelectorName($(field.widget.id));
			}

			var node = $('ue_summary_'+field.key);
			if(node) appendClear(node, text(val));
		}
	}

	var table = $('ue_summary_table');
	uEditFleshSummaryAddresses( table, patron );
	uEditFleshSummaryStatCats( table, patron );
	uEditFleshSummarySurveys( table, patron );
}



var uEditSummaryAddrRow;
function uEditFleshSummaryAddresses( table, patron ) {

	var addrtbody = $n(table, 'ue_summary_addr_tbody');
	if(!uEditSummaryAddrRow)
		uEditSummaryAddrRow = 
			addrtbody.removeChild($n(addrtbody, 'ue_summary_addr_row'));
	var rowtmpl = uEditSummaryAddrRow;
	removeChildren(addrtbody);

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
	$n(row, 'incorporated').appendChild(text( (address.within_city_limits()) ? yes : no ));

	$n(row, 'mailing').appendChild(text( 
		(patron.mailing_address() == address.id()) ? yes : no ));

	$n(row, 'billing').appendChild(text( 
		(patron.billing_address() == address.id()) ? yes : no ));
}



var uEditSummaryStatCatRow;
function uEditFleshSummaryStatCats( table, patron ) {
	var tbody = $n(table, 'ue_summary_stats_tbody');

	if(!uEditSummaryStatCatRow)
		uEditSummaryStatCatRow = 
			tbody.removeChild($n(tbody, 'ue_summary_stats_row'));
	var rowtmpl = uEditSummaryStatCatRow;
	removeChildren(tbody);

	for( var s in patron.stat_cat_entries() ) {
		row = rowtmpl.cloneNode(true);
		var entry = patron.stat_cat_entries()[s];
		var cat = statCatsCache[entry.stat_cat()];
		$n(row, 'ue_summary_stat_name').appendChild(text(cat.name()));
		$n(row, 'ue_summary_stat_value').appendChild(text(entry.stat_cat_entry()));
		row.setAttribute('statcat', entry.stat_cat());
		if( entry.isdeleted() ) addCSSClass(row, 'deleted'); 
		tbody.appendChild(row);
	}

	if( ! getElementsByTagNameFlat( tbody, 'tr' )[0] )
		hideMe(tbody.parentNode);
	else
		unHideMe(tbody.parentNode);
}



var uEditSummarySurveyRow;
function uEditFleshSummarySurveys( table, patron ) {

	var tbody	= $n(table, 'ue_summary_survey_tbody');
	if(!uEditSummarySurveyRow)
		uEditSummarySurveyRow = 
			tbody.removeChild($n(tbody, 'ue_summary_survey_row'));
	var rowtmpl = uEditSummarySurveyRow;

	removeChildren(tbody);

	for( var r in patron.survey_responses() ) {
		var row		= rowtmpl.cloneNode(true);
		var resp		= patron.survey_responses()[r];
		var survey	= surveysCache[resp.survey()];
		var quest	= surveyQuestionsCache[resp.question()];
		var answer	= surveyAnswersCache[resp.answer()];
		$n(row, 'ue_summary_survey_name').appendChild(text(survey.name()));
		$n(row, 'ue_summary_survey_question').appendChild(text(quest.question()));
		$n(row, 'ue_summary_survey_answer').appendChild(text(answer.answer()));
		tbody.appendChild(row);
	}

	if( ! getElementsByTagNameFlat(tbody, 'tr')[0])
		hideMe(tbody.parentNode);
	else
		unHideMe(tbody.parentNode);
}


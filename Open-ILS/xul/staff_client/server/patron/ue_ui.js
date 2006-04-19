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
		insertSelectorVal(selector, -1, answer.answer(), answer.id() );
	}

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



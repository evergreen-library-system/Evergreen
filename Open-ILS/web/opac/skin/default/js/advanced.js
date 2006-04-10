/* advanced search interface */

attachEvt("common", "run", advInit);

/* tests the cookie rresult stuff 

function advTestCookie() {
	var ids = [ 
		40791, 40792, 40793, 40794, 40795, 40797, 40798, 40799, 362178, 362179, 
		362180, 362170, 338215, 333398, 329010, 17, 362182, 362183, 362184, 362185 ];

	cookieManager.write(COOKIE_RIDS, js2JSON(ids), '+1h');
	var a = {};
	a.page = RRESULT;
	a[PARAM_RTYPE] = RTYPE_COOKIE;
	goTo(buildOPACLink(a));
}
*/



function advInit() { 

	depthSelInit(); 

	/*
	var wiz = [
		'advanced.wizard.contains',
		'advanced.wizard.nocontains',
		'advanced.wizard.exact',
		'search_type_selector',
		'advanced.wizard.form_selector' ];
	for( var node in wiz ) 
		setEnterFunc( $(wiz[node]), advWizardRun );

	var ref = [
		'advanced.refined.title_contains',
		'advanced.refined.author_contains',
		'advanced.refined.subject_contains',
		'advanced.refined.series_contains',
		'advanced.refined.form_selector',
		'advanced.refined.series_type',
		'advanced.refined.subject_type',
		'advanced.refined.author_type',
		'advanced.refined.title_type' ];
	for( var i in ref ) 
		setEnterFunc( $(ref[i]), advRefinedRun );
		*/

	setEnterFunc($('opac.advanced.quick.isbn'), advISBNRun );
	setEnterFunc($('opac.advanced.quick.issn'), advISSNRun );
	setEnterFunc($('opac.advanced.quick.cn'), advCNRun );
	setEnterFunc( $n( $('advanced.marc.tbody'), 'advanced.marc.value'), advMARCRun );
}


/*
function advWizardRun() {
	var contains = $('advanced.wizard.contains').value;
	var nocontains = $('advanced.wizard.nocontains').value; 
	var exact	= $('advanced.wizard.exact').value; 
	var form		= getSelectorVal($('advanced.wizard.form_selector'));
	var type		= getSelectorVal($('search_type_selector'));
	var sort		= getSelectorVal($('advanced.wizard.sort_by'));
	var sortdir	= getSelectorVal($('advanced.wizard.sort_dir'));

	var arg = {};
	arg.page = MRESULT;
	arg[PARAM_FORM]		= form;
	arg[PARAM_STYPE]		= type;
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_DEPTH]		= depthSelGetDepth();
	arg[PARAM_LOCATION]	= depthSelGetNewLoc();
	arg[PARAM_TERM]		= advBuildSearch( contains, nocontains, exact );
	arg[PARAM_SORT]		= sort;
	arg[PARAM_SORT_DIR]	= sortdir;

	if( sort == SORT_TYPE_PUBDATE ) {
		arg.page = RRESULT;
		arg[PARAM_RTYPE]	= type;
	}

	if(!arg[PARAM_TERM]) return;

	goTo(buildOPACLink(arg));
}

function advBuildSearch( contains, nocontains, exact ) {
	var string = "";
	if(contains) string = contains;

	if( exact ) {
		if(exact.indexOf('"') > -1) string += " " + exact;
		else string += " \"" + exact + "\"";
	}

	if(nocontains) {
		var words = nocontains.split(" ");
		for( var i in words ) 
			string += " -" + words[i];
	}
	return string;
}


function advRefinedRun() {
	var title	= $('advanced.refined.title_contains').value;
	var author	= $('advanced.refined.author_contains').value;
	var subject = $('advanced.refined.subject_contains').value;
	var series	= $('advanced.refined.series_contains').value;
	var form = getSelectorVal($('advanced.refined.form_selector'));
	var sort		= getSelectorVal($('advanced.refined.sort_by'));
	var sortdir	= getSelectorVal($('advanced.refined.sort_dir'));

	var blob = {};
	title = advRefinedTerm('title', title);
	author = advRefinedTerm('author', author);
	subject = advRefinedTerm('subject', subject);
	series = advRefinedTerm('series', series);

	if(title) { blob.title = {}; blob.title.term =  title; }
	if(author) { blob.author = {}; blob.author.term = author;}
	if(subject) { blob.subject = {}; blob.subject.term = subject;}
	if(series) { blob.series = {}; blob.series.term = series; }

	if( !(title || author|| subject|| series) ) return;

	var arg					= {};
	arg.page					= MRESULT;
	arg[PARAM_FORM]		= form;
	arg[PARAM_STYPE]		= "";
	arg[PARAM_TERM]		= "";
	arg[PARAM_ADVTERM]	= js2JSON(blob);
	arg[PARAM_DEPTH]		= depthSelGetDepth();
	arg[PARAM_LOCATION]	= depthSelGetNewLoc();
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_ADVTYPE]	= ADVTYPE_MULTI;
	arg[PARAM_SORT]		= sort;
	arg[PARAM_SORT_DIR]	= sortdir;

	if( sort == SORT_TYPE_PUBDATE ) {
		arg.page = RRESULT;
		arg[PARAM_RTYPE] = RTYPE_MULTI;
	}

	goTo(buildOPACLink(arg));

}
*/

function advISBNRun() {
	var isbn = $('opac.advanced.quick.isbn').value;
	if(!isbn) return;
	var arg					= {};
	arg.page					= MRESULT;
	arg[PARAM_STYPE]		= "";
	arg[PARAM_TERM]		= "";
	arg[PARAM_ADVTERM]	= isbn;
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_ADVTYPE]	= ADVTYPE_ISBN;
	goTo(buildOPACLink(arg));
}

function advISSNRun() {
	var issn = $('opac.advanced.quick.issn').value;
	if(!issn) return;
	var arg					= {};
	arg.page					= MRESULT;
	arg[PARAM_STYPE]		= "";
	arg[PARAM_TERM]		= "";
	arg[PARAM_ADVTERM]	= issn;
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_ADVTYPE]	= ADVTYPE_ISSN;
	goTo(buildOPACLink(arg));
}

function advCNRun() {
	var cn = $('opac.advanced.quick.cn').value;
	if(!cn) return;
	var arg			= {};
	arg.page			= CNBROWSE;
	arg[PARAM_CN]	= cn;
	goTo(buildOPACLink(arg));
}


/*
function advRefinedTerm( type, term ) {
	var t = getSelectorVal($('advanced.refined.' + type + '_type'));
	var string;

	if( t == 'contains' ) string = advBuildSearch( term );
	else if( t == 'nocontains' ) string = advBuildSearch( null, term );
	else if( t == 'exact' ) string = advBuildSearch( null, null, term );

	return string;
}
*/


function advAddMARC() {
	var newrow = $('advanced.marc.template').cloneNode(true);
	$n(newrow, 'advanced.marc.tag').value = "";
	$n(newrow, 'advanced.marc.subfield').value = "";
	$n(newrow, 'advanced.marc.value').value = "";
	$('advanced.marc.tbody').insertBefore(newrow, $('advanced.marc.submit.row'));
}

function advMARCRun() {

	var t = $('advanced.marc.tbody');
	var searches = [];

	var children = t.getElementsByTagName('tr');
	for( var c in children ) {
		var child = children[c];
		if(!(child && child.innerHTML)) continue;
		var val = advExtractMARC(child);
		if(val) searches.push(val);
	}

	if(searches.length == 0) return;

	var arg = {};
	arg.page = RRESULT;
	arg[PARAM_FORM] = 'all'
	arg[PARAM_RTYPE] = RTYPE_MARC;
	arg[PARAM_OFFSET] = 0;
	arg[PARAM_DEPTH]	= depthSelGetDepth();
	arg[PARAM_LOCATION]	= depthSelGetNewLoc();
	arg[PARAM_SEARCHES] = js2JSON(searches);
	arg[PARAM_ADVTYPE] = ADVTYPE_MARC;
	arg[PARAM_TERM] = "";

	goTo(buildOPACLink(arg));
}


/* EXAMPLE => {"term":"0516011901","restrict":[{"tag":"020","subfield":"a"}]} */
function advExtractMARC(row) {
	if(!row || row.id == 'advanced.marc.submit.row') return null;
	var term = $n(row, 'advanced.marc.value').value;
	if(!term) return null;

	var subfield = $n(row, 'advanced.marc.subfield').value;
	if(!subfield) subfield = "_";

	var tag = $n(row, 'advanced.marc.tag').value;
	if(!tag) return null;

	return { 'term' : term, 'restrict' :  [ { 'tag' : tag, 'subfield' : subfield } ] };
}


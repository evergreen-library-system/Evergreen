/* advanced search interface */

attachEvt("common", "run", advInit);

function advInit() { 

	/* propogate these? */
	clearSearchParams();

	depthSelInit(); 
	setEnterFunc($('opac.advanced.quick.isbn'), advISBNRun );
	setEnterFunc($('opac.advanced.quick.issn'), advISSNRun );
	setEnterFunc($('opac.advanced.quick.cn'), advCNRun );
	setEnterFunc( $n( $('advanced.marc.tbody'), 'advanced.marc.value'), advMARCRun );

	unHideMe($('adv_quick_search_sidebar'));
	if(isXUL()) 
		setSelector($('adv_quick_type'), 'tcn');
	setEnterFunc($('adv_quick_text'), advGenericSearch);
}

function advISBNRun() {
	var isbn = $('opac.advanced.quick.isbn').value;
	if(!isbn) return;
	var arg					= {};
	arg.page					= RRESULT;
	arg[PARAM_STYPE]		= "";
	arg[PARAM_TERM]		= "";
	arg[PARAM_RTYPE]		= RTYPE_ISBN;
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_ADVTERM]	= isbn;
	goTo(buildOPACLink(arg));
}

function advISSNRun() {
	var issn = $('opac.advanced.quick.issn').value;
	if(!issn) return;
	var arg					= {};
	arg.page					= RRESULT;
	arg[PARAM_STYPE]		= "";
	arg[PARAM_TERM]		= "";
	arg[PARAM_ADVTERM]	= issn;
	arg[PARAM_OFFSET]		= 0;
	arg[PARAM_RTYPE]		= RTYPE_ISSN;
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

function advGenericSearch() {
	var type = getSelectorVal($('adv_quick_type'));
	var term = $('adv_quick_text').value;
	if(!term) return;

	var arg = {};

	switch(type) {

		case 'isbn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_RTYPE]		= RTYPE_ISBN;
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_ADVTERM]	= term
			break;
		
		case 'issn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_ADVTERM]	= term;
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_RTYPE]		= RTYPE_ISSN;
			break;

		case 'tcn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_ADVTERM]	= term;
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_RTYPE]		= RTYPE_TCN;
			break;


		case 'cn':
			arg.page			= CNBROWSE;
			arg[PARAM_CN]	= term;
			break;

		default: alert('not done yet');

	}

	if(arg.page) goTo(buildOPACLink(arg));
}



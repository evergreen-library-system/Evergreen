var cgi					= null;
var advanced			= false;
var SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
var FETCH_ID_TYPES	= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
var FETCH_GROUPS		= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
var UPDATE_PATRON		= 'open-ils.actor:open-ils.actor.patron.update';
var defaultState		= 'GA';
var counter				= 0;
var dataFields;
var patron;
var identTypesCache	= {};


/* fetch the necessary data to start off */
function uEditInit() {

	cgi		= new CGI();
	session	= cgi.param('ses');
	if(cgi.param('adv')) advanced = true 
	if(!session) throw "User session is not defined";


	fetchUser(session);
	$('uedit_user').appendChild(text(USER.usrname()));
	uEditShowPage('uedit_userid');

	setTimeout( function() { uEditBuild(); }, 20 );
}


function uEditBuild() {
	//fetchHighestPermOrgs( SESSION, USER.id(), myPerms );

	/* these have to be synchronous */
	uEditBuildLibSelector();

	patron = fetchFleshedUser(cgi.param('usr'));
	if(!patron) patron = uEditNewPatron();

	uEditDraw( 
		uEditFetchIdentTypes(),
		uEditFetchGroups(),
		uEditFetchStatCats(),
		uEditFetchSurveys() );
}


/* creates a new patron object with card attached */
function uEditNewPatron() {
	var patron = new au(); 
	patron.isnew(1);
	patron.id(-1);
	card = new ac();
	card.id(-1);
	patron.card(card);
	patron.cards([card]);
	patron.stat_cat_entries([]);
	patron.survey_responses([]);
	return patron;
}


/* ------------------------------------------------------------------------------ */
/* Fetch code
/* ------------------------------------------------------------------------------ */
function uEditFetchIdentTypes() {
	var req = new Request(FETCH_ID_TYPES);
	req.send(true);
	return req.result();
}

function uEditFetchStatCats() {
	var req = new Request(SC_FETCH_ALL, SESSION);
	req.send(true);
	return req.result();
}

function uEditFetchSurveys() {
	var req = new Request(SV_FETCH_ALL, SESSION);
	req.send(true);
	return req.result();
}

function uEditFetchGroups() {
	var req = new Request(FETCH_GROUPS);
	req.send(true);
	return req.result();
}
/* ------------------------------------------------------------------------------ */


function uEditBuildLibSelector( node, depth, selector ) {
	if(!selector) selector = $('ue_org_selector');
	if(!node) { depth = 0; node = globalOrgTree; }
	
	var opt = insertSelectorVal( selector, -1, node.name(), node.id(), null, depth++ );

	if(!findOrgType(node.ou_type()).can_have_users()) opt.disabled = true; 

	if( node.id() == USER.ws_ou() ) 
		setSelector(selector, node.id());

	for( var c in node.children() ) 
		uEditBuildLibSelector(node.children()[c], depth, selector);
}

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





function uEditDraw(identTypes, groups, statCats, surveys ) {

	hideMe($('uedit_loading'));
	unHideMe($('ue_maintd'));

	uEditDrawIDTypes(identTypes);
	uEditDefineData(patron, identTypes, groups, statCats, surveys );

	for( var f in dataFields ) 
		uEditActivateField(dataFields[f]);
}


/** Applies the event handlers and set the data for the field */
function uEditActivateField(field) {

	if( field.widget.id ) {
		field.widget.node = $(field.widget.id);

	} else {
		field.widget.node = 
			$n(field.widget.base, field.widget.name);
	}

	uEditSetOnchange(field);

	var val = field.object[field.key]();
	if(val == null) return;

	if( field.widget.type == 'input' )
		field.widget.node.value = val;

	if( field.widget.type == 'select' )
		setSelector(field.widget.node, val);

	if( field.widget.type == 'checkbox' )
		field.widget.node.checked = 
			(val && val != 'f') ? true : false;

	if( field.widget.onload ) 
		field.widget.onload(val);
}


function uEditSetOnchange(field) {
	var func = function() {uEditOnChange( field );}
	field.widget.node.onchange = func;
	field.widget.node.onkeyup = func;
}

function uEditNodeVal(field) {
	if(field.widget.type == 'input')
		return field.widget.node.value;

	if(field.widget.type == 'checkbox')
		return field.widget.node.checked;

	if(field.widget.type == 'select')
		return getSelectorVal(field.widget.node);
}


function uEditOnChange(field) {
	var newval = uEditNodeVal(field);

	if(newval) {

		if(field.widget.regex) { 
			if(newval.match(field.widget.regex)) 
				removeCSSClass(field.widget.node, CSS_INVALID_DATA);
			else
				addCSSClass(field.widget.node, CSS_INVALID_DATA);

		} else {
			removeCSSClass(field.widget.node, CSS_INVALID_DATA);
		}

	} else {

		if(field.required) {
			addCSSClass(field.widget.node, CSS_INVALID_DATA);

		} else {
			removeCSSClass(field.widget.node, CSS_INVALID_DATA);
		}
	}

	field.object[field.key](newval);
	field.object.ischanged(1);

	if(field.widget.onpostchange)
		field.widget.onpostchange(field, newval);
}

function uEditFindFieldByKey(key) {
	var fields = grep( dataFields,
		function(item) { return (item.key == key); });
	return (fields) ? fields[0] : null;
}

function uEditFindFieldByWId(id) {
	var fields = grep( dataFields,
		function(item) { return (item.widget.id == id); });
	return (fields) ? fields[0] : null;
}

function uEditSaveUser() {

	var req = new Request(UPDATE_PATRON, SESSION, patron);
	req.send(true);
	var result = req.result();

	if( checkILSEvent(result) ) 
		alert(js2JSON(result));
	else 
		alert($('ue_success').innerHTML);

	if (window.xulG && typeof window.xulG.save == 'function') {
		window.xulG.on_save(patron); 
	}
}



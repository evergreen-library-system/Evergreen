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
var identTypesCache			= {};
var statCatsCache				= {};
var surveysCache				= {};
var surveyQuestionsCache	= {};
var surveyAnswersCache		= {};
var groupsCache				= {};


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



/* fetches necessary and builds the UI */
function uEditBuild() {
	//fetchHighestPermOrgs( SESSION, USER.id(), myPerms );


	/*
	xulG.new_tab('about:blank',{},{});
	 spawn_search()
	*/



	uEditBuildLibSelector();
	patron = fetchFleshedUser(cgi.param('usr'));
	if(!patron) patron = uEditNewPatron(); 


	uEditDraw( 
		uEditFetchIdentTypes(),
		uEditFetchGroups(),
		uEditFetchStatCats(),
		uEditFetchSurveys() );

	if(patron.isnew()) uEditCreateNewAddr();
}


/* creates a new patron object with card attached */
function uEditNewPatron() {
	var patron = new au(); 
	patron.isnew(1);
	patron.id(-1);
	card = new ac();
	card.id(-1);
	card.isnew(1);
	patron.card(card);
	patron.cards([card]);
	patron.stat_cat_entries([]);
	patron.survey_responses([]);
	patron.addresses([]);
	patron.home_ou(USER.ws_ou());
	return patron;
}

/* Creates a new blank address, adds it to the user and the fields array */
var uEditVirtualAddrId = -1;
function uEditCreateNewAddr() {
	var addr = new aua();
	addr.id(uEditVirtualAddrId--);
	addr.isnew(1);
	addr.usr(patron.id());
	addr.state(defaultState);
	addr.country(defaultCountry);
	if(patron.addresses().length == 0) {
		patron.mailing_address(addr);
		patron.billing_address(addr);
	}
	uEditBuildAddrFields(patron, addr);
	patron.addresses().push(addr);
	uEditIterateFields(function(f) { uEditCheckValid(f); });
	uEditCheckErrors();
}


/* kicks off the UI drawing */
function uEditDraw(identTypes, groups, statCats, surveys ) {
	hideMe($('uedit_loading'));
	unHideMe($('ue_maintd'));

	dataFields = [];
	uEditDrawIDTypes(identTypes);
	uEditDrawGroups(groups);
	uEditDrawStatCats(statCats);
	uEditDrawSurveys(surveys);
	uEditDefineData(patron);

	uEditIterateFields(function(f) { uEditActivateField(f) });
	uEditIterateFields(function(f) { uEditCheckValid(f); });
	uEditCheckErrors();
}


/** Applies the event handlers and sets the data for the field */
function uEditActivateField(field) {

	if( field.widget.id ) {
		field.widget.node = $(field.widget.id);

	} else {
		field.widget.node = 
			$n(field.widget.base, field.widget.name);
	}

	uEditSetOnchange(field);

	if(field.widget.onblur) {
		field.widget.node.onblur = 
			function() { field.widget.onblur(field); };
	}

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

	/*
	alert(field.key);
	if(field.key == 'ident_value') alert(field.widget.onblur);
	*/

}


/* set up the onchange event for the field */
function uEditSetOnchange(field) {
	var func = function() {uEditOnChange( field );}
	field.widget.node.onchange = func;

	if(field.widget.type != 'select')
		field.widget.node.onkeyup = func;
}

/* find the current value of the field object's widget */
function uEditNodeVal(field) {
	if(field.widget.type == 'input')
		return field.widget.node.value;

	if(field.widget.type == 'checkbox')
		return field.widget.node.checked;

	if(field.widget.type == 'select')
		return getSelectorVal(field.widget.node);
}


/* update a field value */
function uEditOnChange(field) {

	var newval = uEditNodeVal(field);
	field.object[field.key](newval);
	field.object.ischanged(1);

	if(field.widget.onpostchange)
		field.widget.onpostchange(field, newval);


	uEditIterateFields(function(f) { uEditCheckValid(f); });
	uEditCheckErrors();
}


function uEditCheckValid(field) {
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
}

/* find a field object by object key */
function uEditFindFieldByKey(key) {
	var fields = grep( dataFields,
		function(item) { return (item.key == key); });
	return (fields) ? fields[0] : null;
}

/* find a list of fields by object key */
function uEditFindFieldsByKey(key) {
	return grep( dataFields,
		function(item) { return (item.key == key); });
}

/* find a field object by widget id */
function uEditFindFieldByWId(id) {
	var fields = grep( dataFields,
		function(item) { return (item.widget.id == id); });
	return (fields) ? fields[0] : null;
}


function uEditIterateFields(callback) {
	for( var f in dataFields ) {
		callback(dataFields[f]);
	}
}


function uEditGetErrorStrings() {
	var errors = [];
	uEditIterateFields(
		function(field) { 
			if(field.errkey) {
				if( field.widget.node.className.indexOf(CSS_INVALID_DATA) != -1) {
					var str = $(field.errkey).innerHTML;
					if(str) errors.push(str);
				}
			}
		}
	);

	if(errors[0]) return errors;
	return null;
}

function uEditAlertErrors() {
	var errors = uEditGetErrorStrings();
	if(!errors) return false;
	alert(errors.join("\n"));
	return true;
}


/* send the user to the database */
function uEditSaveUser() {

	if(uEditGetErrorStrings()) {
		uEditAlertErrors();
		return;
	}

	alert(patron.ident_type2());
	alert(patron.ischanged());

	var req = new Request(UPDATE_PATRON, SESSION, patron);
	req.send(true);
	var result = req.result();

	if( checkILSEvent(result) ) 
		alert(js2JSON(result));
	else 
		alert($('ue_success').innerHTML);

	if (window.xulG && typeof window.xulG.save == 'function') {
		window.xulG.on_save(patron); 
	} else {
		location.href = location.href;
	}
}


var uEditDupHashes = {};
function uEditRunDupeSearch(type, search_hash) {

	if(!patron.isnew()) return;
	_debug('dup search: ' + js2JSON(search_hash));

	var linkid = 'ue_dups_'+type;
	var hitsid = linkid + '_hits';
	var req = new Request(PATRON_SEARCH, SESSION, search_hash);

	req.callback( 

		function(r) {
			var ids = r.getResultObject();
			_debug('dup search results: ' + js2JSON(ids));

			if(!(ids && ids[0])) {
				uEditDupHashes[type] = null;
				hideMe($(linkid));
				return;
			}

			unHideMe($(linkid));
			appendClear($(hitsid), text(ids.length));
			uEditDupHashes[type] = search_hash;
			switch(type) {
				case 'ident1' :
					if(confirm($('ue_dup_ident1').innerHTML)) 
						uEditShowSearch(type);
					break;
			}
		}
	);
	req.send();
}


function uEditShowSearch(type) {
	if(window.xulG)
		window.xulG.spawn_search(uEditDupHashes[type]);	
	else alert('Search would be:\n' + js2JSON(uEditDupHashes[type]));
}


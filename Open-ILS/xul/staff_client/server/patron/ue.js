var cgi							= null;
var clone						= false;
var patron						= null;
var counter						= 0;
var identTypesCache			= {};
var statCatsCache				= {};
var surveysCache				= {};
var surveyQuestionsCache	= {};
var surveyAnswersCache		= {};
var userCache					= {};
var groupsCache				= {};
var netLevelsCache			= {};


/* fetch the necessary data to start off */
function uEditInit() {

	cgi		= new CGI();
	session	= cgi.param('ses');
	clone		= cgi.param('clone');
	if(!session) throw "User session is not defined";

	fetchUser(session);
	$('uedit_user').appendChild(text(USER.usrname()));

	setTimeout( function() { 
		uEditBuild(); uEditShowPage('uedit_userid'); }, 20 );
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

function uEditFetchNetLevels() {
	var req = new Request(FETCH_NET_LEVELS, SESSION);
	req.send(true);
	return req.result();
}
/* ------------------------------------------------------------------------------ */



/* fetches necessary and builds the UI */
function uEditBuild() {
	//fetchHighestPermOrgs( SESSION, USER.id(), myPerms );

	uEditBuildLibSelector();
	patron = fetchFleshedUser(cgi.param('usr'));
	if(!patron) patron = uEditNewPatron(); 


	uEditDraw( 
		uEditFetchIdentTypes(),
		uEditFetchGroups(),
		uEditFetchStatCats(),
		uEditFetchSurveys(),
		uEditFetchNetLevels()
		);

	if(patron.isnew()) {
		if(clone) 
			uEditClone(clone);
		else 
			uEditCreateNewAddr();
	}

	if(!patron.isnew()) {
		$('ue_barcode').disabled = true;
		unHideMe($('ue_mark_card_lost'));
		unHideMe($('ue_reset_pw'));
	}
}


/* creates a new patron object with card attached */
var uEditCardVirtId = -1;
function uEditNewPatron() {
	var patron = new au(); 
	patron.isnew(1);
	patron.id(-1);
	card = new ac();
	card.id(uEditCardVirtId--);
	card.isnew(1);
	patron.card(card);
	patron.cards([card]);
	patron.stat_cat_entries([]);
	patron.survey_responses([]);
	patron.addresses([]);
	patron.home_ou(USER.ws_ou());
	uEditMakeRandomPw(patron);
	return patron;
}

function uEditMakeRandomPw(patron) {
	var rand  = Math.random();
	rand = parseInt(rand * 10000) + '';
	while(rand.length < 4) rand += '0';
	appendClear($('ue_password_plain'),text(rand));
	unHideMe($('ue_password_gen'));
	patron.passwd(rand);
	return rand;
}

function uEditResetPw() { 
	var pw = uEditMakeRandomPw(patron);	
	$('ue_password1').value = pw;
	$('ue_password2').value = pw;
}

function uEditClone(clone) {

	var cloneUser = fetchFleshedUser(clone);
	patron.usrgroup(cloneUser.usrgroup());

	if( cloneUser.day_phone() )
		$('ue_day_phone').value = cloneUser.day_phone();
	if( cloneUser.evening_phone() )
		$('ue_night_phone').value = cloneUser.evening_phone();
	if( cloneUser.other_phone() )
		$('ue_other_phone').value = cloneUser.other_phone();
	setSelector($('ue_org_selector'), cloneUser.home_ou());


	setSelector($('ue_profile'), cloneUser.profile());

	/* force the expire date to be set */
	$('ue_profile').onchange();

	for( var a in cloneUser.addresses() ) {
		var addr = cloneUser.addresses()[a];
		if( addr.id() == cloneUser.mailing_address().id() )
			patron.mailing_address(addr);
		if( addr.id() == cloneUser.billing_address().id() )
			patron.billing_address(addr);
		patron.addresses().push(addr);
	}

	uEditBuildAddrs(patron);
}


/* Creates a new blank address, 
	adds it to the user and the fields array */
var uEditVirtualAddrId = -1;
function uEditCreateNewAddr() {
	var addr = new aua();
	addr.id(uEditVirtualAddrId--);
	addr.isnew(1);
	addr.usr(patron.id());
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
function uEditDraw(identTypes, groups, statCats, surveys, netLevels ) {
	hideMe($('uedit_loading'));
	unHideMe($('ue_maintd'));

	dataFields = [];
	uEditDrawIDTypes(identTypes);
	uEditDrawGroups(groups);
	uEditDrawStatCats(statCats);
	uEditDrawSurveys(surveys);
	uEditDrawNetLevels(netLevels);
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

	field.widget.node.disabled = field.widget.disabled;
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


	/* munge up something for all of the required surveys 
		(which are not registered with the fields) */

	/* AWAITS POLICY DECISION */

	/*
	var rows = $('ue_survey_table').getElementsByTagName('tr');
	for( var r in rows ) {

		var row = rows[r];
		var sel = $n(row, 'ue_survey_answer');
		if(!sel) continue;
		var qstn = row.getAttribute('question');

		if(qstn) {
			qstn		= surveyQuestionsCache[qstn];
			survey	= surveysCache[qstn.survey()];
			var val	= getSelectorVal(sel);
			if(!val && survey.required() && survey.required() != 'f')
				errors.push($('ue_bad_survey').innerHTML);
		}
	}
	*/

	/* ------------------------------------------------------------ */

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
function uEditSaveUser(cloneme) {

	if(uEditGetErrorStrings()) {
		uEditAlertErrors();
		return;
	}

	/* null is unique in the db, but '' is not */
	if( ! patron.ident_value() ) patron.ident_value(null);
	if( ! patron.ident_value2() ) patron.ident_value2(null);

	var req = new Request(UPDATE_PATRON, SESSION, patron);
	req.send(true);
	var newuser = req.result();

	if( checkILSEvent(newuser) ) 
		alert(js2JSON(newuser));
	else 
		alert($('ue_success').innerHTML);

	if(cloneme) {
		/* if the user we just created was a clone, and we want to clone it,
		we really want to clone the original */
		if( clone ) cloneme = clone;
		else cloneme = newuser.id();
	}

	if (window.xulG && typeof window.xulG.on_save == 'function') {
		window.xulG.on_save(newuser, cloneme); 

	} else {

		var href = location.href;

		href = href.replace(/\&?usr=\d+/, '');
		href = href.replace(/\&?clone=\d+/, '');

		if( cloneme ) href += '&clone=' + cloneme;
		location.href = href;
	}
}

function uEditCancel() {
	var href = location.href;
	href = href.replace(/\&?usr=\d+/, '');
	href = href.replace(/\&?clone=\d+/, '');
	location.href = href;
}


var uEditDupHashes = {};
var uEditDupTemplate;

function uEditRunDupeSearch(type, search_hash) {

	if(!patron.isnew()) return;

	_debug('dup search: ' + js2JSON(search_hash));

	var req = new Request(PATRON_SEARCH, SESSION, search_hash);

	var container = $('dup_div_container');
	if(!uEditDupTemplate)
		uEditDupTemplate = container.removeChild($('dup_div'));

	/* clear any existing dups for this type */
	iterate( container.getElementsByTagName('div'),
		function(d) {
			if( d.getAttribute('type') == type ) {
				container.removeChild(d)
				return;
			}
		}
	);

	/*req.callback(uEditHandleDupResults);*/
	req.callback(
		function(r) {
			uEditHandleDupResults( r.getResultObject(), search_hash, type, container );
		}
	);
	req.send();
}


function uEditHandleDupResults(ids, search_hash, type, container) {

	_debug('dup search results: ' + js2JSON(ids));

	if(!(ids && ids[0]))  /* no results */
		return uEditDupHashes[type] = null;

	/* add a dup link to the UI and plug in the data */
	var node = uEditDupTemplate.cloneNode(true);
	container.appendChild(node);
	node.setAttribute('type', type);

	var link = $n(node, 'link');
	link.setAttribute('type', type);
	unHideMe(link);
	$n(node,'count').appendChild(text(ids.length));

	for( var o in search_hash ) 
		$n(node, 'data').appendChild(
			text(search_hash[o].value + ' '));

	uEditDupHashes[type] = search_hash;

	switch(type) {
		case 'ident1' :
			if(confirm($('ue_dup_ident1').innerHTML)) 
				uEditShowSearch(type);
			break;
	}
}


function uEditShowSearch(link) {
	var type = link.getAttribute('type');
	if(window.xulG)
		window.xulG.spawn_search(uEditDupHashes[type]);	
	else alert('Search would be:\n' + js2JSON(uEditDupHashes[type]));
}

function uEditMarkCardLost() {

	for( var c in patron.cards() ) {

		var card = patron.cards()[c];
		if( patron.card().id() == card.id() ) {

			/* de-activite the current card */
			card.ischanged(1);
			card.active(0);

			/* create a new card for the patron */
			var newcard = new ac();
			newcard.id(uEditCardVirtId--);
			newcard.isnew(1);
			patron.card(newcard);
			patron.cards().push(newcard);


			/* reset the widget */
			var field = uEditFindFieldByWId('ue_barcode');
			field.widget.node.disabled = false;
			field.widget.node.value = "";
			field.widget.node.onchange();
			field.object = newcard;
		}
	}
}



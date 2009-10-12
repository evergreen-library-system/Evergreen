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
var orgSettings             = [];
//var guardianNote				= null;
var uEditUsePhonePw = false;

if(!window.xulG) var xulG = null;

function $(id) { return document.getElementById(id); }

/* fetch the necessary data to start off */
function uEditInit() {

	_debug('uEditInit(): ' + location.search);

	cgi		= new CGI();
	session	= cgi.param('ses'); 
	if (xulG) if (xulG.ses) session = xulG.ses;
	if (xulG) if (xulG.params) if (xulG.params.ses) session = xulG.params.ses;
	clone		= cgi.param('clone'); 
	if (xulG) if (xulG.clone) clone = xulG.clone;
	if (xulG) if (xulG.params) if (xulG.params.clone) clone = xulG.params.clone;
	if(!session) throw $("patronStrings").getString('web.staff.patron.ue.session_no_defined');

	fetchUser(session);
	$('uedit_user').appendChild(text(USER.usrname()));

	setTimeout( function() { 
		uEditBuild(); uEditShowPage('uedit_userid'); }, 20 );
}

function uEditSetUnload() {
   _debug('setting window unload event');
   /*
   window.onbeforeunload = function(evt) { 
      return $('ue_unsaved_changes').innerHTML; 
   };
   */
}

function uEditClearUnload() {
   _debug('clearing window unload event');
   /*
   window.onbeforeunload = null;
   */
}

/* ------------------------------------------------------------------------------ */
/* Fetch code
/* ------------------------------------------------------------------------------ */
function uEditFetchIdentTypes() {
	_debug("uEditFetchIdentTypes()");
	var s = fetchXULStash(); 
	if (typeof s.list != 'undefined') 
		if (typeof s.list.cit != 'undefined') return s.list.cit;
	var req = new Request(FETCH_ID_TYPES);
	req.send(true);
	return req.result();
}

function uEditFetchStatCats() {
	_debug("uEditFetchStatCats()");
	var s = fetchXULStash(); 
	if (typeof s.list != 'undefined') 
		if (typeof s.list.my_actsc != 'undefined') return s.list.my_actsc;
	var req = new Request(SC_FETCH_ALL, SESSION);
	req.send(true);
	return req.result();
}

function uEditFetchSurveys() {
	_debug("uEditFetchSurveys()");
	var s = fetchXULStash(); 
	if (typeof s.list != 'undefined') 
		if (typeof s.list.asv != 'undefined') return s.list.asv;
	var req = new Request(SV_FETCH_ALL, SESSION);
	req.send(true);
	return req.result();
}

function uEditFetchGroups() {
	_debug("uEditFetchGroups()");
	var s = fetchXULStash(); 
	if (typeof s.tree != 'undefined') 
		if (typeof s.tree.pgt != 'undefined') return s.tree.pgt;
	var req = new Request(FETCH_GROUPS);
	req.send(true);
	return req.result();
}

function uEditFetchNetLevels() {
	_debug("uEditFetchNetLevels()");
	var s = fetchXULStash(); 
	if (typeof s.list != 'undefined') 
		if (typeof s.list.cnal != 'undefined') return s.list.cnal;
	var req = new Request(FETCH_NET_LEVELS, SESSION);
	req.send(true);
	return req.result();
}

/* ------------------------------------------------------------------------------ */


/*  
 * adds all of the group.application_perm's to the list 
 * provided by descending through the group tree 
 */
function buildAppPermList(list, group) {
	if(!group) return;
	if(group.application_perm() ) 
        list.push(group.application_perm());
    for(i in group.children()) {
        buildAppPermList(list, group.children()[i]);
    }
}

/* fetches necessary objects and builds the UI */
function uEditBuild() {

    myPerms = ['BAR_PATRON', 'UNBAR_PATRON'];

    /*  grab the groups before we check perms so we know what
        application_perms to check */
    var groups = uEditFetchGroups();
    buildAppPermList(myPerms, groups);

    // de-dupe the permission list
    var perms = [];
    for(var p in myPerms) 
        if(perms.indexOf(myPerms[p]) == -1)
           perms.push(myPerms[p]);
    myPerms = perms;
        
	fetchHighestPermOrgs( SESSION, USER.id(), myPerms );

	uEditBuildLibSelector();
	var usr = cgi.param('usr'); 
	if (xulG) if (xulG.usr) usr = xulG.usr;
	if (xulG) if (xulG.params) if (xulG.params.usr) usr = xulG.params.usr;

    orgSettings = fetchBatchOrgSetting(USER.ws_ou(), [
        'global.juvenile_age_threshold',
        'patron.password.use_phone'
    ]);

    uEditUsePhonePw = (orgSettings['patron.password.use_phone'] && 
        orgSettings['patron.password.use_phone'].value);

	patron = fetchFleshedUser(usr);
	if(!patron) patron = uEditNewPatron(); 
    
    // jscalendar doesn't like the date format.  trim the time data
    if(patron.dob()) patron.dob( patron.dob().replace(/T.*/, '') );
	
	uEditDraw( 
		uEditFetchIdentTypes(),
        groups,
		uEditFetchStatCats(),
		uEditFetchSurveys(),
		uEditFetchNetLevels()
		);

	if(patron.isnew()) {
		if(clone) uEditClone(clone);
		else uEditCreateNewAddr();

	} else {

		/* do we need to display the parent / gurdian field? */
		uEditCheckDOB(uEditFindFieldByKey('dob'));

		$('ue_barcode').disabled = true;
		unHideMe($('ue_mark_card_lost'));
		unHideMe($('ue_reset_pw'));
		uEditCheckEditPerm();
	}

    uEditCheckBarredPerm();
}

function uEditCheckBarredPerm() {
	if(PERMS['BAR_PATRON'] != -1) 
        return;

    if(isTrue(patron.barred()) && PERMS['UNBAR_PATRON'] != -1) 
        return;

    $('ue_barred').disabled = true;
}


/* if this user does not have permission to put users into
	the edited users group, they do not have permission to 
	edit this user */
function uEditCheckEditPerm() {

	var perm = uEditFindGroupPerm(groupsCache[patron.profile()]);	
	/*
	_debug("editing user with group app perm "+patron.profile()+' : '+
		groupsCache[patron.profile()].name() +', and perm = ' + perm);
		*/

	if(PERMS[perm] != -1) return;

	/* we can edit our own account, but not others in our group */
	if( patron.id() != USER.id() ){
		_debug("we are not allowed to edit this user");
	
		$('ue_save').disabled = true;
		$('ue_save_clone').disabled = true;
		$('ue_mark_card_lost').disabled = true;
		$('ue_reset_pw').disabled = true;
	
		uEditIterateFields(
			function(f) {
				if( f && f.widget && f.widget.node )
					f.widget.node.disabled = true;
			}	
		);	

	}

	var node = $('ue_profile').parentNode;
	node.removeChild($('ue_profile'));
	node.appendChild(elem('span',null,groupsCache[patron.profile()].name()));

	var field = uEditFindFieldByKey('profile');
	field.required = false;
	removeCSSClass(field.widget.node, CSS_INVALID_DATA);
	uEditCheckErrors();
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
    patron.net_access_level(defaultNetLevel);
	patron.stat_cat_entries([]);
	patron.survey_responses([]);
	patron.addresses([]);
	patron.home_ou(USER.ws_ou());
	uEditMakeRandomPw(patron);
	return patron;
}

function uEditMakeRandomPw(patron) {
    if(uEditUsePhonePw) return;
	var rand  = Math.random();
	rand = parseInt(rand * 10000) + '';
	while(rand.length < 4) rand += '0';
	appendClear($('ue_password_plain'),text(rand));
	unHideMe($('ue_password_gen'));
	patron.passwd(rand);
	return rand;
}

function uEditMakePhonePw() {
    if(patron.passwd()) return;
    if( (pw = patron.day_phone()) || 
        (pw = patron.evening_phone()) || (pw = patron.other_phone()) ) {
            pw = pw.substring(pw.length - 4); // this is iffy
            uEditResetPw(pw);
	        appendClear($('ue_password_plain'), text(pw));
	        unHideMe($('ue_password_gen'));
	        patron.passwd(pw);
    }
}

function uEditResetPw(pw) { 
    if(!pw) pw = uEditMakeRandomPw(patron);	
	$('ue_password1').value = pw;
	$('ue_password2').value = pw;
    $('ue_password1').onchange();
}

function uEditClone(clone) {

	var cloneUser = fetchFleshedUser(clone);
	patron.usrgroup(cloneUser.usrgroup());

	if( cloneUser.day_phone() ) {
		$('ue_day_phone').value = cloneUser.day_phone();
	    $('ue_day_phone').onchange();
    }

	if( cloneUser.evening_phone() ) {
		$('ue_night_phone').value = cloneUser.evening_phone();
		$('ue_night_phone').onchange();
    }

	if( cloneUser.other_phone() ) {
		$('ue_other_phone').value = cloneUser.other_phone();
		$('ue_other_phone').onchange();
    }

	setSelector($('ue_org_selector'), cloneUser.home_ou());
	setSelector($('ue_profile'), cloneUser.profile());

	/* force the expire date to be set */
	$('ue_profile').onchange();
	$('ue_org_selector').onchange();

	for( var a in cloneUser.addresses() ) {
		var addr = cloneUser.addresses()[a];
		if( cloneUser.mailing_address && 
				addr.id() == cloneUser.mailing_address().id() )
			patron.mailing_address(addr);
		if( cloneUser.billing_address() &&
				addr.id() == cloneUser.billing_address().id() )
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

	if(!patron.addresses()) 
		patron.addresses([]);

	if(patron.addresses().length == 0) {
		patron.mailing_address(addr);
		patron.billing_address(addr);
	}

	addr.valid(1);
	addr.within_city_limits(1);

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
	uEditDrawGroups(groups, null, null, true);
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
	if(field.object == null) return;
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

	//_debug(field.key+' = '+newval);

	uEditIterateFields(function(f) { uEditCheckValid(f); });
	uEditCheckErrors();

   uEditSetUnload();
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
	for( var f in dataFields ) 
		callback(dataFields[f]);
}


function uEditGetErrorStrings() {
	var errors = [];
	uEditIterateFields(
		function(field) { 
			if(field.errkey) {
				if( !field.object.isdeleted() ) {
					if( field.widget.node.className.indexOf(CSS_INVALID_DATA) != -1) {
						var str = $(field.errkey).innerHTML;
						if(str) errors.push(str);
					}
				}
			}
		}
	);

	/* munge up something for all of the required surveys 
		(which are not registered with the fields) */
	if( patron.isnew() ) {
		var sel = $('ue_survey_table');

		if( sel ) {
			var rows = sel.getElementsByTagName('tr');

			for( var r in rows ) {
		
				var row = rows[r];
				var sel = $n(row, 'ue_survey_answer');
				if(!sel) continue;
				var qstn = row.getAttribute('question');
		
				if(qstn) {
					qstn		= surveyQuestionsCache[qstn];
					survey	= surveysCache[qstn.survey()];
					var val	= getSelectorVal(sel);
					if(!val && isTrue(survey.required()))
						errors.push($('ue_bad_survey').innerHTML + ' : ' + qstn.question());
				}
			}
		}
	}

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
	//if( ! patron.ident_type2() ) patron.ident_type2(null);
	if( ! patron.ident_value2() ) patron.ident_value2(null);
	patron.ident_type2(null);

	if(! patron.dob() ) patron.dob(null);

	_debug("Saving patron with card: " + js2JSON(patron.card()));
	_debug("Saving full patron: " + js2JSON(patron));

	//for( var c in patron

	var req = new Request(UPDATE_PATRON, SESSION, patron);
	req.alertEvent = false;
	req.send(true);
	var newuser = req.result();

   uEditClearUnload();

	var evt;
	if( (evt = checkILSEvent(newuser)) || ! newuser ) {
		if(evt) {
            evt = newuser;
            if( evt.textcode == 'XACT_COLLISION' ) {
                if( confirmId('ue_xact_collision') )
                    location.href = location.href;
                return;
            }
            var j = js2JSON(evt);
			alert(j);
			_debug("USER UPDATE FAILED:\n" + j);
		}
		return;
	} 

	alert($('ue_success').innerHTML);

	if(cloneme) {
		/* if the user we just created was a clone, and we want to clone it,
		we really want to clone the original */
		if( clone ) cloneme = clone;
		else cloneme = newuser.id();
	}


	if( cloneme ) {

		if(window.xulG &&
			typeof window.xulG.spawn_editor == 'function' && 

			!patron.isnew() ) {
				_debug("xulG clone spawning new interface...");
				var ses = cgi.param('ses'); 
				if (xulG) if (xulG.ses) ses = xulG.ses;
				if (xulG) if (xulG.params) if (xulG.params.ses) ses = xulG.params.ses;
				window.xulG.spawn_editor({ses:ses,clone:cloneme});
				uEditRefresh();

		} else {

			var href = location.href;
			href = href.replace(/\&?usr=\d+/, '');
			href = href.replace(/\&?clone=\d+/, '');
			href += '&clone=' + cloneme;
			location.href = href;
		}

	} else {

		uEditRefresh();
	}

	uEditRefreshXUL(newuser);
}


function uEditRefreshXUL(newuser) {
	if (window.xulG && typeof window.xulG.on_save == 'function') 
		window.xulG.on_save(newuser);
}

function uEditRefresh() {
	var href = location.href;
	href = href.replace(/\&?clone=\d+/, '');
	location.href = href;
}


function uEditCancel() {
	var href = location.href;
	href = href.replace(/\&?usr=\d+/, '');
	href = href.replace(/\&?clone=\d+/, '');
	var id = cgi.param('usr'); 
	if (xulG) if (xulG.usr) id = xulG.usr;
	if (xulG) if (xulG.params) if (xulG.params.usr) id = xulG.params.usr;
	/* reload the current user if available */
	if( id ) href += (href.match(/\?/) ? "&" : "?") + "usr=" + id;
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
		case 'ident' :
			if(confirm($('ue_dup_ident1').innerHTML)) 
				uEditShowSearch(null, type);
			break;
	}
}


function uEditShowSearch(link,type) {
	if(!type) type = link.getAttribute('type');
	if(window.xulG)
		window.xulG.spawn_search(uEditDupHashes[type]);	
	else alert($("patronStrings").getString('web.staff.patron.ue.uedit_show_search.search_would_be', js2JSON(uEditDupHashes[type])));
}

function uEditMarkCardLost() {

	for( var c in patron.cards() ) {

		var card = patron.cards()[c];
		if( patron.card().id() == card.id() ) {

			/* de-activite the current card */
			card.ischanged(1);
			card.active(0);

			if( !card.barcode() ) {
				/* a card exists in the array with no barcode */
				ueRemoveCard(card.id());

			} else if( card.isnew() && card.active() == 0 ) {
				/* a new card was created, then never used, removing.. */
				_debug("removing new inactive card "+card.barcode());
				ueRemoveCard(card.id());
			}

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
			_debug("uEditMarkCardLost(): created new card object for user");
		}
	}
}


function ueRemoveCard(id) {
	_debug("removing card from cards() array: " + id);
	var cds = grep( patron.cards(), function(c){return (c.id() != id)});
	if(!cds) cds = [];
	for( var j = 0; j < cds.length; j++ )
		_debug("patron card array now has :  "+cds[j].id());
	patron.cards(cds);
}



function compactArray(arr) {
	var a = [];
	for( var i = 0; arr && i < arr.length; i++ ) {
		if( arr[i] != null )
			a.push(arr[i]);
	}
	return a;
}

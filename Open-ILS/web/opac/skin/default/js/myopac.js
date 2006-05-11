
attachEvt("common", "run", myOPACInit );
attachEvt("common", "loggedIn", myOPACInit );

attachEvt('common','locationUpdated', myopacReload );

var fleshedUser = null;
var fleshedContainers = {};
var holdCache = {};


function clearNodes( node, keepArray ) {
	if(!node) return;
	for( var n in keepArray ) node.removeChild(keepArray[n]);
	removeChildren(node);
	for( var n in keepArray ) node.appendChild(keepArray[n]);
}

function myOPACInit() {
	if(!(G.user && G.user.session)) initLogin();
	else myOPACChangePage( "summary" );
}

function myopacReload() {
	swapCanvas($('myopac_reloading'));
	var a = {};
	a[PARAM_LOCATION] = getNewSearchLocation();
	a[PARAM_DEPTH] = getNewSearchDepth();
	goTo(buildOPACLink(a, true));
}


function myOPACChangePage( page ) {
	
	var s = $("myopac_summary_td");
	var c = $("myopac_checked_td");
	var f = $("myopac_fines_td");
	var h = $("myopac_holds_td");
	var p = $("myopac_prefs_td");
	var b = $('myopac_bookbag_td');

	var ss = $("myopac_summary_div");
	var cc = $("myopac_checked_div");
	var ff = $("myopac_fines_div");
	var hh = $("myopac_holds_div");
	var pp = $("myopac_prefs_div");
	var bb = $('myopac_bookbag_div');

	var cls = "myopac_link";
	var acls = "myopac_link_active";

	hideMe(ss);
	hideMe(cc); hideMe(ff);
	hideMe(hh); hideMe(pp);
	hideMe(bb);

	removeCSSClass(s, acls );
	removeCSSClass(c, acls );
	removeCSSClass(f, acls );
	removeCSSClass(h, acls );
	removeCSSClass(p, acls );
	removeCSSClass(b, acls );

	switch( page ) {

		case "summary": 
			unHideMe(ss);
			addCSSClass(s, acls );
			myOPACShowSummary();
			break;

		case "checked": 
			unHideMe(cc);
			addCSSClass(c, acls );
			myOPACShowChecked();
			break;

		case "holds": 
			unHideMe(hh);
			addCSSClass(h, acls );
			myOPACShowHolds();
			break;

		case "fines": 
			unHideMe(ff);
			addCSSClass(f, acls );
			myOPACShowFines();
			break;

		case "prefs": 
			unHideMe(pp);
			addCSSClass(p, acls );
			myOPACShowPrefs();
			break;

		case 'bookbag':
			unHideMe(bb);
			addCSSClass(b, acls);
			myOPACShowBookbags();
			break;
	}
}

function myOPACShowChecked() {
	if(checkedDrawn) return;
	var req = new Request(FETCH_CHECKED_OUT_SLIM, G.user.session);	
	req.callback(myOPACDrawCheckedOutSlim);
	req.send();

	var nreq = new Request(FETCH_NON_CAT_CIRCS, G.user.session);
	nreq.callback(myOPACDrawNonCatCircs);
	nreq.send();
}


var checkedRowTemplate;
var circsCache = new Array();
var checkedDrawn = false;

function myOPACDrawCheckedOutSlim(r) {

	var checked			= r.getResultObject();
	var tbody			= $("myopac_checked_tbody");
	var loading			= $("myopac_checked_loading");
	var none				= $("myopac_checked_none");

	if(checkedDrawn) return;
	checkedDrawn = true;
	if(!checkedRowTemplate) 
		checkedRowTemplate = tbody.removeChild($("myopac_checked_row"));

	clearNodes( tbody, [ loading, none ] );

	hideMe(loading); /* remove all children and start over */
	if(!(checked && checked[0])) unHideMe(none);

	for( var idx in checked ) {

		var circ    = checked[idx]
		var row = checkedRowTemplate.cloneNode(true);
		row.id = 'myopac_checked_row_ ' + circ.id();

 		var due = circ.due_date();
      due = due.replace(/[0-9][0-9]:.*$/,"");

		var dlink = $n( row, "myopac_checked_due" );
		var rlink = $n( row, "myopac_checked_renewals" );
		var rnlink = $n( row, "myopac_checked_renew_link" );

		dlink.appendChild(text(due));
		rlink.appendChild(text(circ.renewal_remaining()));
		unHideMe(row);
		rnlink.setAttribute('href', 'javascript:myOPACRenewCirc("'+circ.id()+'");');
		circsCache.push(circ);

		tbody.appendChild(row);

		var req = new Request(FETCH_MODS_FROM_COPY, circ.target_copy() );
		req.request.alertEvent = false;
		req.request.circ = circ.id();
		req.request.copy = circ.target_copy();
		req.callback(myOPACDrawCheckedTitle);
		req.send();
	}
}

function myOPACDrawCheckedTitle(r) {
	var record = r.getResultObject();
	var circid = r.circ;

	if(!record || checkILSEvent(record)) {
		var req = new Request( FETCH_COPY, r.copy );
		req.request.circ = circid
		req.callback(myOPACDrawNonCatalogedItem);
		req.send();
		return;
	}

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );
	buildTitleDetailLink(record, tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), alink);
}

function myOPACDrawNonCatalogedItem(r) {
	var copy = r.getResultObject();
	var circid = r.circ;

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );

	tlink.parentNode.appendChild(text(copy.dummy_title()));
	alink.parentNode.appendChild(text(copy.dummy_author()));
}


function myOPACRenewCirc(circid) {

	var circ;
	for( var i = 0; i != circsCache.length; i++ ) 
		if(circsCache[i].id() == circid)
			circ = circsCache[i];

	if(!confirm($('myopac_renew_confirm').innerHTML)) return;

	var req = new Request(RENEW_CIRC, G.user.session, 
		{ patron : G.user.id(), copyid : circ.target_copy() } );
	req.send(true);
	var res = req.result();

	if(checkILSEvent(res)) {
		alertILSEvent(res);
		return;
	}

	alert($('myopac_renew_success').innerHTML);	
	checkedDrawn = false;
	myOPACShowChecked();
}



function myOPACShowHolds() {
	var req = new Request(FETCH_HOLDS, G.user.session, G.user.id());	
	req.callback(myOPACDrawHolds);
	req.send();
}

var holdsTemplateRowOrig;
var holdsTemplateRow;
function myOPACDrawHolds(r) {

	var tbody = $("myopac_holds_tbody");
	if(holdsTemplateRow) return;
	if(holdsTemplateRowOrig) {
		holdsTemplateRow = holdsTemplateRowOrig;
		removeChildren(tbody);
	} else {
		holdsTemplateRow = tbody.removeChild($("myopac_holds_row"));
		holdsTemplateRowOrig = holdsTemplateRow;
	}

	hideMe($('myopac_holds_loading'));

	var holds = r.getResultObject();

	if(!holds || holds.length < 1) unHideMe($('myopac_holds_none'));
	for( var i = 0; i != holds.length; i++ ) {

		var h = holds[i];
		holdCache[h.id()] = h;

		var row = holdsTemplateRow.cloneNode(true);
		row.id = "myopac_holds_row_" + h.id() + '_' + h.target();

		var formats = (h.holdable_formats()) ? h.holdable_formats() : null;
		var form = $n(row, "myopac_holds_formats");
		form.id = "myopac_holds_form_" + h.id() + '_' + h.target();
		if(formats) form.appendChild(text(formats));

		var orglink = $n(row, "myopac_holds_location");
		orglink.appendChild(text(findOrgUnit(h.pickup_lib()).name()));

		tbody.appendChild(row);

		$n(row,'myopac_holds_cancel_link').setAttribute(
			'href','javascript:myOPACCancelHold("'+ h.id()+'");'); 

		$n(row,'myopac_holds_edit_link').setAttribute(
			'href','javascript:myOPACEditHold("'+ h.id()+'");'); 

		unHideMe(row);

		myOPACDrawHoldTitle(h);
		myOPACDrawHoldStatus(h);
	}
}

function myOPACEditHold(holdid) {
	var hold = holdCache[holdid];
	holdsDrawWindow(hold.target(), hold.hold_type(), hold, 
		function(){
			holdsTemplateRow = null;
			myOPACShowHolds();
		}
	);
}


function myOPACCancelHold(holdid) {
	if( confirm($('myopac_holds_cancel_verify').innerHTML) ) {
		holdsCancel(holdid);
		holdsTemplateRow = null
		myOPACShowHolds();
	}
}


function myOPACDrawHoldStatus(hold) {
	var req = new Request(FETCH_HOLD_STATUS, G.user.session, hold.id() );
	req.callback(myOShowHoldStatus);
	req.request.hold = hold;
	req.send();
}

function myOShowHoldStatus(r) {

	var hold = r.hold;
	var status = r.getResultObject();
	var row = $("myopac_holds_row_" + r.hold.id() + '_' + r.hold.target());

	if( status < 3 )
		unHideMe($n(row, 'hold_status_waiting'));

	if( status == 3 )
		unHideMe($n(row, 'hold_status_transit'));

	if( status == 4 )
		unHideMe($n(row, 'hold_status_available'));
}

function myOPACDrawHoldTitle(hold) {
	var method;
	if(hold.hold_type() == "M") method = FETCH_MRMODS;
	if(hold.hold_type() == "T") method = FETCH_RMODS;
	var req = new Request(method, hold.target());
	req.callback(myOPACFleshHoldTitle);
	req.request.hold = hold.id();
	req.send();
}

function myOPACFleshHoldTitle(r) {

	var record = r.getResultObject();
	var row = $("myopac_holds_row_" + r.hold + '_' + record.doc_id());
	var title_link = $n(row, "myopac_holds_title_link");
	var author_link = $n(row, "myopac_holds_author_link");

	buildTitleDetailLink(record, title_link);
	buildSearchLink(STYPE_AUTHOR, record.author(), author_link);

	var form = $("myopac_holds_form_" + r.hold + '_' + record.doc_id());

	if(form) {
		var img = elem("img");
		img.setAttribute("src", 
			buildImageLink('tor/' + record.types_of_resource()[0] + ".jpg"));
		addCSSClass(img, "myopac_form_pic");
		form.appendChild(img);
	}
}

var finesShown = false;
function myOPACShowFines() {
	if(finesShown) return; finesShown = true;
	var req = new Request(FETCH_FINES_SUMMARY, G.user.session, G.user.id() );
	req.callback(_myOPACShowFines);
	req.send();
}

function _myOPACShowFines(r) {
	hideMe($('myopac_fines_summary_loading'));
	unHideMe($('myopac_fines_summary_row'));

	var summary = r.getResultObject();
	var total	= "0.00"; /* localization? */
	var paid		= "0.00";
	var balance = "0.00";
	if( instanceOf(summary,mous) ) {

		total		= _finesFormatNumber(summary.total_owed());
		paid		= _finesFormatNumber(summary.total_paid());
		balance	= _finesFormatNumber(summary.balance_owed());

		var req = new Request(FETCH_TRANSACTIONS, G.user.session, G.user.id() );
		req.callback(myOPACShowTransactions);
		req.send();
	}

	$('myopac_fines_summary_total').appendChild(text(total));
	$('myopac_fines_summary_paid').appendChild(text(paid));
	$('myopac_fines_summary_balance').appendChild(text(balance));
}

function _finesFormatNumber(num) {
	if(isNull(num)) num = 0;
	num = num + "";
	if(num.length < 2 || !num.match(/\./)) num += ".00";
	if(num.match(/\./) && num.charAt(num.length-2) == '.') num += "0";
	return num;
}          

function _trimTime(time) { if(!time) return ""; return time.replace(/\ .*/,""); }

function _trimSeconds(time) { if(!time) return ""; return time.replace(/:\d\d\..*$/,""); }

function myOPACShowTransactions(r) {

	if(myopacGenericTransTemplate || myopacCircTransTemplate) return;

	var transactions = r.getResultObject();

	for( var idx in transactions ) {

		var trans	= transactions[idx].transaction;
		var record	= transactions[idx].record;
		var circ		= transactions[idx].circ;

		if(trans.xact_type() == 'circulation') 
			myOPACShowCircTransaction(trans, record, circ);

		else if(trans.xact_type() == 'grocery' ) 
			myopacShowGenericTransaction( trans );
	}
}

var myopacGenericTransTemplate;
function myopacShowGenericTransaction( trans ) {
	var tbody = $('myopac_trans_tbody');

	if(!myopacGenericTransTemplate) {
		myopacGenericTransTemplate = 
			tbody.removeChild($('myopac_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacGenericTransTemplate.cloneNode(true);

	$n(row,'myopac_trans_start').appendChild(
			text(_trimSeconds(trans.xact_start())));

	$n(row,'myopac_trans_last_payment').appendChild(
			text(_trimSeconds(trans.last_payment_ts())));

	$n(row,'myopac_trans_init_amount').appendChild(
			text(_finesFormatNumber(trans.total_owed())));

	$n(row,'myopac_trans_total_paid').appendChild(
			text(_finesFormatNumber(trans.total_paid())));

	$n(row,'myopac_trans_balance').appendChild(
			text(_finesFormatNumber(trans.balance_owed())));

	var req = new Request(FETCH_MONEY_BILLING, G.user.session, trans.id());
	req.send(true);
	var bills = req.result();
	if(bills && bills[0])
		$n(row,'myopac_trans_bill_type').appendChild(
				text(bills[0].billing_type()));

	tbody.appendChild(row);
	unHideMe($('myopac_trans_div'));
}



/* draws a circulation transaction summary */
var myopacCircTransTemplate;
function myOPACShowCircTransaction(trans, record, circ) {
	var tbody = $('myopac_circ_trans_tbody');

	if(!myopacCircTransTemplate) {
		myopacCircTransTemplate = tbody.removeChild($('myopac_circ_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacCircTransTemplate.cloneNode(true);

	buildTitleDetailLink(record, $n(row,'myopac_circ_trans_title'));

	$n(row,'myopac_circ_trans_author').appendChild(text(
		normalize(truncate(record.author(), 65))));

	$n(row,'myopac_circ_trans_start').
		appendChild(text(_trimTime(trans.xact_start())));

   var due = _trimTime(circ.due_date());
	var checkin = _trimTime(circ.stop_fines_time());

	$n(row,'myopac_circ_trans_due').appendChild(text(due))
	if(checkin)
		appendClear($n(row,'myopac_circ_trans_finished'), text(checkin));
	if(circ.stop_fines() == 'LOST')
		appendClear($n(row,'myopac_circ_trans_finished'), text(circ.stop_fines()));
	if(circ.stop_fines() == 'CLAIMSRETURNED')
		appendClear($n(row,'myopac_circ_trans_finished'), text(""));


	$n(row,'myopac_circ_trans_balance').
		appendChild(text(_finesFormatNumber(trans.balance_owed())));

	tbody.appendChild(row);
	unHideMe($('myopac_circ_trans_div'));
}


function myOPACSavePrefs() {
	G.user.prefs[PREF_HITS_PER] = getSelectorVal($('prefs_hits_per'));
	G.user.prefs[PREF_DEF_FONT] = getSelectorVal($('prefs_def_font'));
	G.user.prefs[PREF_HOLD_NOTIFY] = getSelectorVal($('prefs_hold_notify'));
	if(commitUserPrefs())
		alert($('prefs_update_success').innerHTML);
	else alert($('prefs_update_failure').innerHTML);
}


function myOPACShowDefFont() {
	var font;
	if(G.user.prefs[PREF_DEF_FONT])
		font = G.user.prefs[PREF_DEF_FONT];
	else font = "regular";
	setSelector($('prefs_def_font'), font);
}

function myOPACShowHoldNotify() {
	var pref = G.user.prefs[PREF_HOLD_NOTIFY];

	if(pref) {
		if(pref.match(/email/i) && pref.match(/phone/i)) {
			setSelector($('prefs_hold_notify'), 'phone:email');
		} else if( pref.match(/email/i) ) {
			setSelector($('prefs_hold_notify'), 'email');
		} else if( pref.match(/phone/i) ) {
			setSelector($('prefs_hold_notify'), 'phone');
		}

	} else {
		setSelector($('prefs_hold_notify'), 'phone:email');
	}
}

function myOPACShowPrefs() {
	grabUserPrefs();
	myOPACShowHitsPer();
	myOPACShowDefFont();
	myOPACShowHoldNotify();
	hideMe($('myopac_prefs_loading'));
}

function myOPACShowHitsPer() {
	var hits = 10;
	if(G.user.prefs[PREF_HITS_PER])
		hits = G.user.prefs[PREF_HITS_PER];
	var hitsSel = $('prefs_hits_per');
	setSelector(hitsSel, hits);
}

var userShown = false;
function myOPACShowSummary() {
	if(userShown) return; userShown = true;
	var req = new Request(FETCH_FLESHED_USER,G.user.session, G.user.id());
	req.callback(_myOPACSummaryShowUer);
	req.send();
}

var addrRowTemplate;
function _myOPACSummaryShowUer(r) {

	var user = r.getResultObject();
	fleshedUser = user;
	if(!user) return;

	appendClear($('myopac_summary_first'),text(user.first_given_name()));
	appendClear($('myopac_summary_middle'),text(user.second_given_name()));
	appendClear($('myopac_summary_dayphone'),text(user.day_phone()));
	appendClear($('myopac_summary_eveningphone'),text(user.evening_phone()));
	appendClear($('myopac_summary_otherphone'),text(user.other_phone()));
	appendClear($('myopac_summary_last'),text(user.family_name()));
	appendClear($('myopac_summary_username'),text(user.usrname()));
	appendClear($('myopac_summary_email'),text(user.email()));
	appendClear($('myopac_summary_barcode'),text(user.card().barcode()));
	appendClear($('myopac_summary_ident1'),text(user.ident_value()));
	appendClear($('myopac_summary_ident2'),text(user.ident_value2()));
	appendClear($('myopac_summary_homelib'),text(findOrgUnit(user.home_ou()).name()));
	appendClear($('myopac_summary_create_date'),text(user.create_date()));

	var tbody = $('myopac_addr_tbody');
	var template;

	if(addrRowTemplate) { 
		template = addrRowTemplate;
	} else {
		template = tbody.removeChild($('myopac_addr_row'));
		addrRowTemplate = template;
	}
	removeChildren(tbody);

	for( var a in user.addresses() ) {
		var row = template.cloneNode(true);
		myOPACDrawAddr(row, user.addresses()[a]);
		tbody.appendChild(row);
	}
}

function myOPACDrawAddr(row, addr) {

	appendClear($n(row, 'myopac_addr_type'),text(addr.address_type()));
	var street = (addr.street2()) ? addr.street1() + ", " + addr.street2() : addr.street1();
	appendClear($n(row, 'myopac_addr_street'),text(street));
	appendClear($n(row, 'myopac_addr_city'),text(addr.city()));
	appendClear($n(row, 'myopac_addr_county'),text(addr.county()));
	appendClear($n(row, 'myopac_addr_state'),text(addr.state()));
	appendClear($n(row, 'myopac_addr_zip'),text(addr.post_code()));
}


function myOPACUpdateUsername() {
	var username = $('myopac_new_username').value;
	if(username == null || username == "") {
		alert($('myopac_username_error').innerHTML);
		return;
	}
	var req = new Request(UPDATE_USERNAME, G.user.session, username );
	req.send(true);
	if(req.result()) {

		var evt;
		var res = req.result();
		if(evt = checkILSEvent(res)) {
			alertILSEvent(res);
			return;
		}

		G.user.usrname(username);
		hideMe($('myopac_update_username_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_username_failure').innerHTML);
}

function myOPACUpdateEmail() {
	var email = $('myopac_new_email').value;
	if(email == null || email == "") {
		alert($('myopac_email_error').innerHTML);
		return;
	}

	var req = new Request(UPDATE_EMAIL, G.user.session, email );
	req.send(true);
	if(req.result()) {
		G.user.usrname(email);
		hideMe($('myopac_update_email_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_email_failure').innerHTML);
}


function myOPACUpdatePassword() {
	var curpassword = $('myopac_current_password').value;
	var password = $('myopac_new_password').value;
	var password2 = $('myopac_new_password2').value;

	if(	curpassword == null || curpassword == "" || 
			password == null || password == "" || 
			password2 == null || password2 == "" || password != password2 ) {
		alert($('myopac_password_error').innerHTML);
		return;
	}

	if(!strongPassword(password, true)) return;

	var req = new Request(UPDATE_PASSWORD, G.user.session, password, curpassword );
	req.send(true);
	if(req.result()) {
		hideMe($('myopac_update_password_row'));
		userShown = false;
		myOPACShowSummary();
		alert($('pw_update_successful').innerHTML);
		return;
	}

	alert($('myopac_password_failure').innerHTML);
}




var containerTemplate;
function myOPACShowBookbags(force) {

	var tbody =$('myopac_bookbag_tbody') ;

	if(!containerTemplate) 
		containerTemplate = tbody.removeChild($('myopac_bookbag_tr'));
	else if(!force) return;

	removeChildren(tbody);

	var containers = containerFetchAll();

	var found = false;
	for( var i in containers ) {
		found = true;
		var cont = containers[i];
		var row = containerTemplate.cloneNode(true);
		row.id = 'myopac_bookbag_row_' + cont.id();
		var link = $n(row, 'myopac_expand_bookbag');
		var dlink = $n(row, 'myopac_container_delete');
		link.appendChild( text(cont.name()) );
		link.setAttribute('href', 
			'javascript:myOPACExpandBookbag("' + cont.id() + '","' + cont.name() + '");');
		myOPACFetchBBItems( cont.id(), row );
		dlink.setAttribute('href', 'javascript:myOPACDeleteBookbag("'+cont.id()+'");');

		if( cont.pub() ) {
			unHideMe($n(row, 'myopac_bb_published_yes'));
			var link = $n(row, 'myopac_bb_published_view');
			/*
			link.setAttribute('href', buildExtrasLink( 'bbags.xml?bb='+cont.id(), false));  
			*/
			link.setAttribute('href', buildExtrasLink( 'feed/bookbag/html/'+cont.id(), false));  
			link.setAttribute('target', '_blank' );
			unHideMe(link);

			link = $n(row, 'myopac_bb_make_unpublished');
			link.setAttribute('href', 'javascript:myOPACMakeBBPublished("'+cont.id()+'", true);');
			unHideMe(link);

		} else { 
			unHideMe($n(row, 'myopac_bb_published_no')); 
			var link = $n(row, 'myopac_bb_make_published');
			link.setAttribute('href', 'javascript:myOPACMakeBBPublished("'+cont.id()+'");');
			unHideMe(link);
		}

		tbody.appendChild(row);	
	}

	if(!found) unHideMe($('myopac_bookbags_none'));
	else unHideMe($('myopac_bookbag_table'));	
}

function myOPACMakeBBPublished(bbid, hideme) {

	var bb = fleshedContainers[bbid];

	if(hideme) {
		if(!confirm($('myopac_make_unpublished_confirm').innerHTML)) return;
		bb.pub(0);
	} else {
		if(!confirm($('myopac_make_published_confirm').innerHTML)) return;
		bb.pub(1);
	}

	var result = containerUpdate(bb);

	var code = checkILSEvent(result);
	if(code) { alertILSEvent(result); return; }

	if(result) alert($('myopac_bb_update_success').innerHTML);
	myOPACShowBookbags(true);
}



function myOPACDeleteBookbag(id) {
	if( confirm( $('myopac_delete_bookbag_warn').innerHTML ) ) {
		var result = containerDelete(id);
		var code = checkILSEvent(result);
		if(code) { alertILSEvent(result); return; }
		hideMe($('myopac_bookbag_items_table'));
		hideMe($('myopac_bookbag_items_name'));
		hideMe($('myopac_bookbag_no_items'));
		myOPACShowBookbags(true);
	}
}

function myOPACFetchBBItems( id, row, block ) {
	if(!block) {
		containerFlesh( id, _myOPACSetBBItems, { row: row }  );
	} else {
		var cont = containerFlesh(id);
		myOPACSetBBItems( cont, row );
	}
}

function _myOPACSetBBItems(r) { myOPACSetBBItems( r.getResultObject(), r.args.row ); }

function myOPACSetBBItems( container, row ) {
	fleshedContainers[container.id()] = container;
	var node = $n(row, 'myopac_bookbag_item_count');
	removeChildren(node);
	node.appendChild( text(container.items().length) );
}

var BBItemsRow;
function myOPACExpandBookbag( id, name ) {
	
	var tbody = $('myopac_bookbag_items_tbody');
	if(!BBItemsRow) BBItemsRow = tbody.removeChild($('myopac_bookbag_items_row'));
	removeChildren(tbody);
	removeChildren($('myopac_bookbag_items_name'));

	$('myopac_bookbag_items_name').appendChild(text(name));

	if( fleshedContainers[id] ) {
		var len = fleshedContainers[id].items().length;

		if( len == 0 ) {
			unHideMe($('myopac_bookbag_no_items'));
			hideMe($('myopac_bookbag_items_table'));
			return;
		}

		hideMe($('myopac_bookbag_no_items'));
		unHideMe($('myopac_bookbag_items_table'));

		for( var i = 0; i != len; i++ ) {
			var row = BBItemsRow.cloneNode(true);
			found = true;

			var item = fleshedContainers[id].items()[i];
			var tlink = $n(row,'myopac_bookbag_items_title');
			var alink = $n(row,'myopac_bookbag_items_author');

			var req = new Request( FETCH_RMODS, item.target_biblio_record_entry() );
			req.request.tlink = tlink;
			req.request.alink = alink;
			req.callback(myOPACShowBBItem);
			req.send();

			var clink = $n(row, 'myopac_bookbag_items_remove');
			clink.setAttribute('href', 'javascript:myOPACRemoveBBItem("'+item.id()+'","'+id+'","'+name+'");');

			tbody.appendChild(row);
		}
	}
}

function myOPACRemoveBBItem( id, containerid, container_name ) {
	if(!confirm($('myopac_remove_bb_item_confirm').innerHTML)) return;
	containerRemoveItem( id );
	myOPACFetchBBItems( containerid, $('myopac_bookbag_row_' + containerid), true);
	myOPACExpandBookbag( containerid, container_name );
}

function myOPACShowBBItem(r) {
	var record = r.getResultObject();
	buildTitleDetailLink(record, r.tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), r.alink);
}

function myOPACCreateBookbag() {
	var name = $('myopac_bookbag_new_name').value;	
	if(!name) return;

	var exists = false;
	for( var c in fleshedContainers ) { exists = true; break; }

	/* let them know what they are getting into... */
	if(!exists) if(!confirm($('bb_create_warning').innerHTML)) return;

	var result = containerCreate( name, $('bb_public_yes').checked );
	var code = checkILSEvent(result);
	if(code) { alertILSEvent(result); return; }
	myOPACShowBookbags(true);
}


/* ---------------------------------------------------------------------- */
/* Non cat circs */
/* ---------------------------------------------------------------------- */

var nonCatCircIds;
var nonCatTypes;
/* if we have some circs, grab the non-cat types */
function myOPACDrawNonCatCircs(r) {
	var ids = r.getResultObject();
	if(ids.length == 0) return;
	nonCatCircIds = ids;
	unHideMe($('non_cat_circs_div'));
	var req = new Request(FETCH_NON_CAT_TYPES, G.user.home_ou());
	req.callback(myOPACDrawNonCatCircs2);
	req.send();
}


/* now we have circs and the types.. draw each one */
var nonCatTbody;
var nonCatRow;
function myOPACDrawNonCatCircs2(r) {
	nonCatTypes = r.getResultObject();
	nonCatTbody = $('non_cat_circs_tbody');
	if(!nonCatRow) nonCatRow = 
		nonCatTbody.removeChild($('non_cat_circs_row'));
	removeChildren(nonCatTbody);
	for( var i in nonCatCircIds ) {
		var req = new Request(FETCH_NON_CAT_CIRC, G.user.session, nonCatCircIds[i]);
		req.callback(myOPACDrawNonCatCirc);
		req.send();
	}
}


/* draw a single circ */
function myOPACDrawNonCatCirc(r) {
	var circ = r.getResultObject();


	var type = grep(nonCatTypes, 
		function(i){
			return (i.id() == circ.item_type());
		}
	)[0];


	var row = nonCatTbody.appendChild(nonCatRow.cloneNode(true));
	appendClear($n(row, 'circ_lib'), text(findOrgUnit(circ.circ_lib()).name()));
	appendClear($n(row, 'item_type'), text(type.name()));

	var duration = interval_to_seconds(type.circ_duration());
	duration = parseInt(duration + '000');

	var dtf = circ.circ_time();

	/*Date.W3CDTF is not happy with the milliseonds, nor is it
	happy without minute component of the timezone */
	dtf = dtf.replace(/\.\d+/,'');
	dtf += ":00"; 

	var start = new Date.W3CDTF();
	start.setW3CDTF(dtf);
	var due = new Date(  start.getTime() + duration );

	appendClear($n(row, 'circ_time'), text(due));
}





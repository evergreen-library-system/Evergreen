
attachEvt("common", "run", myOPACInit );
attachEvt("common", "loggedIn", myOPACInit );

var fleshedUser = null;


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


function myOPACChangePage( page ) {
	
	var s = $("myopac_summary_td");
	var c = $("myopac_checked_td");
	var f = $("myopac_fines_td");
	var h = $("myopac_holds_td");
	var p = $("myopac_prefs_td");

	var ss = $("myopac_summary_div");
	var cc = $("myopac_checked_div");
	var ff = $("myopac_fines_div");
	var hh = $("myopac_holds_div");
	var pp = $("myopac_prefs_div");

	var cls = "myopac_link";
	var acls = "myopac_link_active";

	hideMe(ss);
	hideMe(cc); hideMe(ff);
	hideMe(hh); hideMe(pp);

	removeCSSClass(s, acls );
	removeCSSClass(c, acls );
	removeCSSClass(f, acls );
	removeCSSClass(h, acls );
	removeCSSClass(p, acls );

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
	}

	/*
	alert('Classes:\n' + s.className + '\n' + c.className + 
		'\n' + h.className + '\n' + f.className + '\n' + p.className);
		*/
}

function myOPACShowChecked() {
	var req = new Request(FETCH_CHECKED_OUT_SLIM, G.user.session);	
	req.callback(myOPACDrawCheckedOutSlim);
	req.send();
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
		req.request.circ = circ.id();
		req.callback(myOPACDrawCheckedTitle);
		req.send();
	}
}

function myOPACDrawCheckedTitle(r) {
	var circid = r.circ;
	var row = $('myopac_checked_row_ ' + circid);
	var record = r.getResultObject();
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );
	buildTitleDetailLink(record, tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), alink);
}


function myOPACRenewCirc(circid) {
	var circ;
	for( var i = 0; i != circsCache.length; i++ ) 
		if(circsCache[i].id() == circid)
			circ = circsCache[i];

	var req = new Request(RENEW_CIRC, G.user.session, circ );
	req.send(true);
	var res = req.result();
	if(res.status) {
		alert(res.text);
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
		var row = holdsTemplateRow.cloneNode(true);
		row.id = "myopac_holds_row_" + h.id() + '_' + h.target();

		var formats = (h.holdable_formats()) ? h.holdable_formats() : null;
		var form = $n(row, "myopac_holds_formats");
		form.id = "myopac_holds_form_" + h.id() + '_' + h.target();
		if(formats) form.appendChild(text(formats));

		$n(row, "myopac_holds_location").
			appendChild(text(findOrgUnit(h.pickup_lib()).name()));
		$n(row, "myopac_holds_email_link").
			appendChild(text(h.email_notify()));
		$n(row, "myopac_holds_phone_link").
			appendChild(text(h.phone_notify()));
		tbody.appendChild(row);

		$n(row,'myopac_holds_cancel_link').setAttribute(
			'href','javascript:myOPACCancelHold("'+ h.id()+'");'); 
		unHideMe(row);

		myOPACDrawHoldTitle(h);
	}
}

function myOPACCancelHold(holdid) {
	if( confirm($('myopac_holds_cancel_verify').innerHTML) ) {
		holdsCancel(holdid);
		holdsTemplateRow = null
		myOPACShowHolds();
	}
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

function _trimSeconds(time) { if(!time) return ""; return time.replace(/\..*/,""); }


var transTemplate;
function myOPACShowTransactions(r) {

	if(transTemplate) return;
	var tbody = $('myopac_fines_tbody');
	unHideMe($('myopac_trans_table'));
	transTemplate = tbody.removeChild($('myopac_trans_row'));

	var transactions = r.getResultObject();

	//alert(js2JSON(transactions));

	for( var idx in transactions ) {

		var trans = transactions[idx].transaction;
		var record = transactions[idx].record;
		var row = transTemplate.cloneNode(transTemplate);

		$n(row,'myopac_trans_start').
			appendChild(text(_trimSeconds(trans.xact_start())));
		$n(row,'myopac_trans_last_bill').
			appendChild(text(_trimSeconds(trans.last_billing_ts())));
		$n(row,'myopac_trans_last_payment').
			appendChild(text(_trimSeconds(trans.last_payment_ts())));
		$n(row,'myopac_trans_init_amount').
			appendChild(text(_finesFormatNumber(trans.total_owed())));
		$n(row,'myopac_trans_total_paid').
			appendChild(text(_finesFormatNumber(trans.total_paid())));
		$n(row,'myopac_trans_balance').
			appendChild(text(_finesFormatNumber(trans.balance_owed())));

		var extra = "";
		var type = trans.xact_type();
		$n(row,'myopac_trans_type').appendChild(text(type));
		if( type == "circulation" ) extra = record.title();
		$n(row, 'myopac_trans_extra').appendChild(text(extra));

		tbody.appendChild(row);
	}
}

function myOPACSavePrefs() {
	G.user.prefs['opac.hits_per_page'] = getSelectorVal($('prefs_hits_per'));
	if(commitUserPrefs())
		alert($('prefs_update_success').innerHTML);
	else alert($('prefs_update_failure').innerHTML);
}


function myOPACShowPrefs() {
	grabUserPrefs();
	myOPACShowHitsPer();
	hideMe($('myopac_prefs_loading'));
	unHideMe($('myopac_prefs_row'));
}

function myOPACShowHitsPer() {
	var hits = 10;
	if(G.user.prefs['opac.hits_per_page'])
		hits = G.user.prefs['opac.hits_per_page'];
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
		if(evt = checkILSEvent(req.result())) {
			alertILSEvent(evt);
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

	var req = new Request(UPDATE_PASSWORD, G.user.session, password, curpassword );
	req.send(true);
	if(req.result()) {
		G.user.usrname(password);
		hideMe($('myopac_update_password_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_password_failure').innerHTML);
}





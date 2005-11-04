
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
	
	var s = getId("myopac_summary_td");
	var c = getId("myopac_checked_td");
	var f = getId("myopac_fines_td");
	var h = getId("myopac_holds_td");
	var p = getId("myopac_prefs_td");

	var ss = getId("myopac_summary_div");
	var cc = getId("myopac_checked_div");
	var ff = getId("myopac_fines_div");
	var hh = getId("myopac_holds_div");
	var pp = getId("myopac_prefs_div");

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

	alert('Classes:\n' + s.className + '\n' + c.className + 
		'\n' + h.className + '\n' + f.className + '\n' + p.className);
}

function myOPACShowChecked() {
	var req = new Request(FETCH_CHECKED_OUT, G.user.session);	
	req.callback(myOPACDrawCheckedOut);
	req.send();
}


var checkedRowTemplate;
function myOPACDrawCheckedOut(r) {


	var checked			= r.getResultObject();
	var tbody			= getId("myopac_checked_tbody");
	var loading			= getId("myopac_checked_loading");
	var none				= getId("myopac_checked_none");

	if(checkedRowTemplate) return;
	checkedRowTemplate = tbody.removeChild(getId("myopac_checked_row"));

	clearNodes( tbody, [ loading, none ] );

	hideMe(loading); /* remove all children and start over */
	if(!(checked && checked[0])) unHideMe(none);

	for( var idx in checked ) {

		var row = checkedRowTemplate.cloneNode(true);

		var circ    = checked[idx].circ;
      var record  = checked[idx].record;
      var copy    = checked[idx].copy;
 		var due = circ.due_date();
      due = due.replace(/[0-9][0-9]:.*$/,"");

		var tlink = findNodeByName( row, "myopac_checked_title_link" );
		var alink = findNodeByName( row, "myopac_checked_author_link" );
		var dlink = findNodeByName( row, "myopac_checked_due" );
		var rlink = findNodeByName( row, "myopac_checked_renewals" );
		var rnlink = findNodeByName( row, "myopac_checked_renew_link" );

		buildTitleDetailLink(record, tlink);
		buildSearchLink(STYPE_AUTHOR, record.author(), alink);
		dlink.appendChild(text(due));
		rlink.appendChild(text(circ.renewal_remaining()));
		unHideMe(row);
		//rnlink /* set the renew action */

		tbody.appendChild(row);
	}
}



function myOPACShowHolds() {
	var req = new Request(FETCH_HOLDS, G.user.session, G.user.id());	
	req.callback(myOPACDrawHolds);
	req.send();
}

var holdsTemplateRow;
function myOPACDrawHolds(r) {

	var tbody = getId("myopac_holds_tbody");
	if(holdsTemplateRow) return;
	holdsTemplateRow = tbody.removeChild(getId("myopac_holds_row"));

	hideMe(getId('myopac_holds_loading'));

	var holds = r.getResultObject();

	if(!holds || holds.length < 1) unHideMe(getId('myopac_holds_none'));
	for( var i = 0; i != holds.length; i++ ) {

		var h = holds[i];
		var row = holdsTemplateRow.cloneNode(true);
		row.id = "myopac_holds_row_" + h.target();

		var formats = (h.holdable_formats()) ? h.holdable_formats() : null;
		var form = findNodeByName(row, "myopac_holds_formats");
		form.id = "myopac_holds_form_" + h.target();
		if(formats) form.appendChild(text(formats));

		findNodeByName(row, "myopac_holds_location").appendChild(text(findOrgUnit(h.pickup_lib()).name()));
		findNodeByName(row, "myopac_holds_email_link").appendChild(text(h.email_notify()));
		findNodeByName(row, "myopac_holds_phone_link").appendChild(text(h.phone_notify()));
		tbody.appendChild(row);
		unHideMe(row);

		myOPACDrawHoldTitle(h);
	}
}

function myOPACDrawHoldTitle(hold) {
	var method;
	if(hold.hold_type() == "M") method = FETCH_MRMODS;
	if(hold.hold_type() == "T") method = FETCH_RMODS;
	var req = new Request(method, hold.target());
	req.callback(myOPACFleshHoldTitle);
	req.send();
}

function myOPACFleshHoldTitle(r) {

	var record = r.getResultObject();
	var row = getId("myopac_holds_row_" + record.doc_id());
	var title_link = findNodeByName(row, "myopac_holds_title_link");
	var author_link = findNodeByName(row, "myopac_holds_author_link");

	buildTitleDetailLink(record, title_link);
	buildSearchLink(STYPE_AUTHOR, record.author(), author_link);

	var form = getId("myopac_holds_form_" + record.doc_id());

	if(form) {
		var img = elem("img");
		img.setAttribute("src", buildImageLink('tor/' + record.types_of_resource()[0] + ".jpg"));
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
	hideMe(getId('myopac_fines_summary_loading'));
	unHideMe(getId('myopac_fines_summary_row'));

	var summary = r.getResultObject();
	var total	= "0.00"; /* localization? */
	var paid		= "0.00";
	var balance = "0.00";
	if( instanceOf(summary,mus) ) {

		total		= _finesFormatNumber(summary.total_owed());
		paid		= _finesFormatNumber(summary.total_paid());
		balance	= _finesFormatNumber(summary.balance_owed());

		var req = new Request(FETCH_TRANSACTIONS, G.user.session, G.user.id() );
		req.callback(myOPACShowTransactions);
		req.send();
	}

	getId('myopac_fines_summary_total').appendChild(text(total));
	getId('myopac_fines_summary_paid').appendChild(text(paid));
	getId('myopac_fines_summary_balance').appendChild(text(balance));
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
	var tbody = getId('myopac_fines_tbody');
	unHideMe(getId('myopac_trans_table'));
	transTemplate = tbody.removeChild(getId('myopac_trans_row'));

	var transactions = r.getResultObject();

	alert(js2JSON(transactions));

	for( var idx in transactions ) {

		var trans = transactions[idx].transaction;
		var record = transactions[idx].record;
		var row = transTemplate.cloneNode(transTemplate);

		findNodeByName(row,'myopac_trans_start').appendChild(text(_trimSeconds(trans.xact_start())));
		findNodeByName(row,'myopac_trans_last_bill').appendChild(text(_trimSeconds(trans.last_billing_ts())));
		findNodeByName(row,'myopac_trans_last_payment').appendChild(text(_trimSeconds(trans.last_payment_ts())));
		findNodeByName(row,'myopac_trans_init_amount').appendChild(text(_finesFormatNumber(trans.total_owed())));
		findNodeByName(row,'myopac_trans_total_paid').appendChild(text(_finesFormatNumber(trans.total_paid())));
		findNodeByName(row,'myopac_trans_balance').appendChild(text(_finesFormatNumber(trans.balance_owed())));

		var extra = "";
		var type = trans.xact_type();
		findNodeByName(row,'myopac_trans_type').appendChild(text(type));
		if( type == "circulation" ) extra = record.title();
		findNodeByName(row, 'myopac_trans_extra').appendChild(text(extra));

		tbody.appendChild(row);
	}
}


function myOPACShowPrefs() {
}

var userShown = false;
function myOPACShowSummary() {
	if(userShown) return; userShown = true;
	var req = new Request(FETCH_FLESHED_USER,G.user.session, G.user.id());
	req.callback(_myOPACSummaryShowUer);
	req.send();
}

function _myOPACSummaryShowUer(r) {

	var user = r.getResultObject();
	fleshedUser = user;

	getId('myopac_summary_first').appendChild(text(user.first_given_name()));
	getId('myopac_summary_middle').appendChild(text(user.second_given_name()));
	getId('myopac_summary_dayphone').appendChild(text(user.day_phone()));
	getId('myopac_summary_eveningphone').appendChild(text(user.evening_phone()));
	getId('myopac_summary_otherphone').appendChild(text(user.other_phone()));
	getId('myopac_summary_last').appendChild(text(user.family_name()));
	getId('myopac_summary_username').appendChild(text(user.usrname()));
	getId('myopac_summary_email').appendChild(text(user.email()));
	getId('myopac_summary_barcode').appendChild(text(user.card().barcode()));
	getId('myopac_summary_ident1').appendChild(text(user.ident_value()));
	getId('myopac_summary_ident2').appendChild(text(user.ident_value2()));
	getId('myopac_summary_homelib').appendChild(text(findOrgUnit(user.home_ou()).name()));
	getId('myopac_summary_create_date').appendChild(text(user.create_date()));

	var tbody = getId('myopac_addr_tbody');
	var template = tbody.removeChild(getId('myopac_addr_row'));
	for( var a in user.addresses() ) {
		var row = template.cloneNode(true);
		myOPACDrawAddr(row, user.addresses()[a]);
		tbody.appendChild(row);
	}
}

function myOPACDrawAddr(row, addr) {
	findNodeByName(row, 'myopac_addr_type').appendChild(text(addr.address_type()));
	var street = (addr.street2()) ? addr.street1() + ", " + addr.street2() : addr.street1();
	findNodeByName(row, 'myopac_addr_street').appendChild(text(street));
	findNodeByName(row, 'myopac_addr_city').appendChild(text(addr.city()));
	findNodeByName(row, 'myopac_addr_county').appendChild(text(addr.county()));
	findNodeByName(row, 'myopac_addr_state').appendChild(text(addr.state()));
	findNodeByName(row, 'myopac_addr_zip').appendChild(text(addr.post_code()));
}





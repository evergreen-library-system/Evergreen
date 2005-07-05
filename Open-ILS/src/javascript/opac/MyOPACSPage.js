/* */

MyOPACSPage.prototype					= new Page();
MyOPACSPage.prototype.constructor	= Page;
MyOPACSPage.baseClass					= Page.constructor;

function MyOPACSPage() {
	var session_id = location.search.substring(  
			location.search.indexOf("session") + 8 ); /*md5 session key*/

	this.user = UserSession.instance();
	this.user.verifySession(session_id);
}

MyOPACSPage.prototype.init = function() {
	this.draw();
}

MyOPACSPage.prototype.draw = function(type) {

	debug("Fleshing User");

	this.infoPane = getById("my_opac_info_pane");
	this.infoTable = getById("my_opac_info_table");
	/*
	removeChildren(this.infoPane);
	removeChildren(this.infoTable);
	this.infoPane.appendChild(this.infoTable);
	*/


	this.buildNavBox(true);
	
	this.checkCell		= getById("my_opac_checked");
	this.holdsCell		= getById("my_opac_holds");
	this.profileCell	= getById("my_opac_profile");
	this.finesCell		= getById("my_opac_fines");

	check		= getById("my_opac_checked_link");
	holds		= getById("my_opac_holds_link");
	profile	= getById("my_opac_profile_link");
	fines		= getById("my_opac_fines_link");

	var obj = this;
	check.onclick		= function() { obj.drawCheckedOut(); };
	holds.onclick		= function() { obj.drawHolds(); };
	profile.onclick	= function() { obj.drawProfile(); };
	fines.onclick		= function() { obj.drawFines(); };

	switch(type) {
		case "holds": this.drawHolds(); break;
		case "profile": this.drawProfile(); break;
		case "fines": this.drawFines(); break;
		case "checked": 
		default:this.drawCheckedOut();
	}
}


MyOPACSPage.prototype.setLink = function(cell) {
	remove_css_class(this.checkCell,	"my_opac_link_cell_active");
	remove_css_class(this.holdsCell,	"my_opac_link_cell_active");
	remove_css_class(this.profileCell, "my_opac_link_cell_active");
	remove_css_class(this.finesCell,	"my_opac_link_cell_active");
	add_css_class(cell, "my_opac_link_cell_active");
}

MyOPACSPage.prototype.drawCheckedOut = function() {
	removeChildren(this.infoTable);
	removeChildren(this.infoPane);
	this.infoPane.appendChild(this.infoTable);
	this.setLink(this.checkCell);
	this.getCheckedOut(_drawCheckedOut);
}

MyOPACSPage.prototype.drawHolds = function() {
	removeChildren(this.infoTable);
	removeChildren(this.infoPane);
	this.infoPane.appendChild(this.infoTable);
	this.setLink(this.holdsCell);
	this._drawHolds();
}

MyOPACSPage.prototype.drawProfile = function() {
	removeChildren(this.infoTable);
	removeChildren(this.infoPane);
	this.infoPane.appendChild(this.infoTable);
	this.setLink(this.profileCell);
	this._drawProfile();
}

MyOPACSPage.prototype.drawFines = function() {
	removeChildren(this.infoTable);
	removeChildren(this.infoPane);
	this.infoPane.appendChild(this.infoTable);
	this.setLink(this.finesCell);
}

function _drawCheckedOut(obj, data) {

	if(data == null) return;
	//obj.infoPane.appendChild(obj.infoTable);
	var circRow = obj.infoTable.insertRow(obj.infoTable.rows.length);

	var tcell = circRow.insertCell(circRow.cells.length)
	tcell.appendChild(mktext("Title"));
	var dcell = circRow.insertCell(circRow.cells.length);
	dcell.appendChild(mktext("Due Date"));
	var drcell = circRow.insertCell(circRow.cells.length);
	drcell.appendChild(mktext("Duration"));
	var bcell = circRow.insertCell(circRow.cells.length);
	bcell.appendChild(mktext("Barcode"));
	var ccell = circRow.insertCell(circRow.cells.length);
	ccell.appendChild(mktext("Circulating Library"));
	var rcell = circRow.insertCell(circRow.cells.length);
	rcell.appendChild(mktext("Renewals Remaining"));
	var rbcell = circRow.insertCell(circRow.cells.length);
	rbcell.appendChild(mktext("Renew?"));

	add_css_class(tcell, "my_opac_info_table_header");
	add_css_class(dcell, "my_opac_info_table_header");
	add_css_class(drcell, "my_opac_info_table_header");
	add_css_class(bcell, "my_opac_info_table_header");
	add_css_class(ccell, "my_opac_info_table_header");
	add_css_class(rcell, "my_opac_info_table_header");
	add_css_class(rbcell, "my_opac_info_table_header");


	if(data.length < 1) {
		debug("No circs exist for this user");
		circRow = obj.infoTable.insertRow(obj.infoTable.rows.length);
		circRow.insertCell(0).appendChild(
			mktext("No items currently checked out"));
		return;
	}

	for( var index in data ) {

		var circ		= data[index].circ;
		var record	= data[index].record;
		var copy		= data[index].copy;
		circRow = obj.infoTable.insertRow(obj.infoTable.rows.length);


		//var due = new Date(parseInt(circ.due_date() + "000")).toLocaleString();
		var due = circ.due_date();

		/* chop the 'time' portion of the date */
		due = due.replace(/[0-9][0-9]:.*$/,"");

		var title_href = createAppElement("a");
		title_href.setAttribute("href","?sub_frame=1&target=record_detail&record=" + record.doc_id() );
		title_href.setAttribute("target","_top"); /* escape to the outermost frame */
		title_href.appendChild(mktext(record.title()));

		var renewbox = elem("input", 
			{type:"checkbox", id:"renew_checkbox_" + record.doc_id()});

		/* grab circ lib name */
		var org = obj._getOrgUnit(copy.circ_lib());
		org = org.name();

		/* for each circulation, build a row of data */
		var titleCell			= circRow.insertCell(circRow.cells.length);
		var dueCell				= circRow.insertCell(circRow.cells.length);
		var durationCell		= circRow.insertCell(circRow.cells.length);
		var barcodeCell		= circRow.insertCell(circRow.cells.length);
		var circLibCell		= circRow.insertCell(circRow.cells.length);
		var renewRemainCell	= circRow.insertCell(circRow.cells.length);
		var renewCell			= circRow.insertCell(circRow.cells.length);

		add_css_class(titleCell, "my_opac_profile_cell");
		add_css_class(dueCell, "my_opac_profile_cell");
		add_css_class(durationCell, "my_opac_profile_cell");
		add_css_class(barcodeCell, "my_opac_profile_cell");
		add_css_class(circLibCell, "my_opac_profile_cell");
		add_css_class(renewRemainCell, "my_opac_profile_cell");
		add_css_class(renewCell, "my_opac_profile_cell");

		titleCell.appendChild(title_href);
		dueCell.appendChild(mktext(due));
		durationCell.appendChild(mktext(circ.duration()));
		barcodeCell.appendChild(mktext(copy.barcode()));
		circLibCell.appendChild(mktext(org));
		renewRemainCell.appendChild(mktext(circ.renewal_remaining()));
		renewCell.appendChild(renewbox);

	}

}


MyOPACSPage.prototype.getCheckedOut = function(callback) {

	/* grab our circs and records */
	var request = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.actor.user.checked_out",
		this.user.getSessionId() );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			if(callback)
				callback(obj, req.getResultObject());
		}
	);

	request.send();
}


MyOPACSPage.prototype._drawProfile = function() {

	this.user.fleshMe(true);
	var infot = elem("table");
	this.infoTable.insertRow(0).insertCell(0).appendChild(infot);
	this.infoTable.insertRow(1).insertCell(0).appendChild(
		elem("div",{id:"my_opac_update_info"}));

	var urow = infot.insertRow(infot.rows.length);
	var prow = infot.insertRow(infot.rows.length);
	var erow = infot.insertRow(infot.rows.length);
	var brow = infot.insertRow(infot.rows.length);
	var arow = infot.insertRow(infot.rows.length);
	var a2row = infot.insertRow(infot.rows.length);

	var ucell	= urow.insertCell(urow.cells.length);
	var ucell2	= urow.insertCell(urow.cells.length);
	var ucell3	= urow.insertCell(urow.cells.length);

	var pcell	= prow.insertCell(prow.cells.length);
	var pcell2	= prow.insertCell(prow.cells.length);
	var pcell3	= prow.insertCell(prow.cells.length);

	var ecell	= erow.insertCell(erow.cells.length);
	var ecell2	= erow.insertCell(erow.cells.length);
	var ecell3	= erow.insertCell(erow.cells.length);

	var bcell	= brow.insertCell(brow.cells.length);
	var bcell2	= brow.insertCell(brow.cells.length);
	var bcell3	= brow.insertCell(brow.cells.length);

	add_css_class(ucell, "my_opac_info_table_header");
	add_css_class(pcell, "my_opac_info_table_header");
	add_css_class(ecell, "my_opac_info_table_header");
	add_css_class(bcell, "my_opac_info_table_header");

	add_css_class(ucell2, "my_opac_profile_cell");
	add_css_class(pcell2, "my_opac_profile_cell");
	add_css_class(ecell2, "my_opac_profile_cell");
	add_css_class(bcell2, "my_opac_profile_cell");

	add_css_class(ucell3, "my_opac_profile_cell");
	add_css_class(pcell3, "my_opac_profile_cell");
	add_css_class(ecell3, "my_opac_profile_cell");
	add_css_class(bcell3, "my_opac_profile_cell");

	var ubold	= elem("b");
	var pbold	= elem("b");
	var ebold	= elem("b");
	var bbold	= elem("b");
	var abold	= elem("b");

	var uclick = elem("a", 
		{id:"uname_link",href:"javascript:void(0);",
		style:"text-decoration:underline;"}, null, "Change");

	var pclick = elem("a", 
		{id:"passwd_link",href:"javascript:void(0);",
		style:"text-decoration:underline;"}, null, "Change");

	var eclick = elem("a", 
		{id:"email_link",href:"javascript:void(0);", 
		style:"text-decoration:underline;"}, null, "Change");

	var obj = this;
	uclick.onclick = function() { obj.updateUsername(); }
	pclick.onclick = function() { obj.updatePassword(); }
	eclick.onclick = function() { obj.updateEmail(); }

	ucell.appendChild(mktext("Username"));
	ubold.appendChild(mktext(this.user.userObject.usrname()));
	ucell2.appendChild(ubold);
	ucell3.appendChild(uclick);

	pcell.appendChild(mktext("Password"));
	pbold.appendChild(mktext("N/A"));
	pcell2.appendChild(pbold);
	pcell3.appendChild(pclick);

	ecell.appendChild(mktext("Email Address"));
	ebold.appendChild(mktext(this.user.userObject.email()));
	ecell2.appendChild(ebold);
	ecell3.appendChild(eclick);

	bcell.appendChild(mktext("Active Barcode"));
	bbold.appendChild(mktext(this.user.userObject.card().barcode()));
	bcell2.appendChild(bbold);
	bcell3.appendChild(mktext(" "));

	var addrTable = elem("table");
	add_css_class(addrTable, "my_opac_addr_table");
	var row = addrTable.insertRow(0);
	var mailing = row.insertCell(0);
	var space = row.insertCell(1);
	var billing = row.insertCell(2);

	space.setAttribute("style","width: 30px");
	space.appendChild(mktext(" "));

	var addr = this.user.userObject.mailing_address();
	mailing.appendChild(this.mkAddrTable("Mailing Address", addr));

	addr = this.user.userObject.billing_address();
	billing.appendChild(this.mkAddrTable("Billing Address", addr));

	this.infoPane.appendChild(elem("br"));
	/*
	this.infoPane.appendChild(elem("hr"));
	this.infoPane.appendChild(elem("br"));
	this.infoPane.appendChild(addrTable);
	*/

}


MyOPACSPage.prototype.mkAddrTable = function(type, addr) {
	var table = elem("table");

	var header_row = table.insertRow(table.rows.length);
	var header_cell = header_row.insertCell(0);
	add_css_class(header_cell,"my_opac_info_table_header");
	header_cell.id = "header_cell";
	header_cell.colSpan = 2;	
	header_cell.setAttribute("colspan", "2");
	header_cell.appendChild(mktext(type));

	var s1row = table.insertRow(table.rows.length);
	var s2row = table.insertRow(table.rows.length);
	var cityrow = table.insertRow(table.rows.length);
	var ziprow = table.insertRow(table.rows.length);
	var staterow = table.insertRow(table.rows.length);

	var s1cell = s1row.insertCell(0);
	var s2cell = s2row.insertCell(0);
	var citycell = cityrow.insertCell(0);
	var zipcell = ziprow.insertCell(0);
	var statecell = staterow.insertCell(0);

	add_css_class(s1cell, "my_opac_info_table_header");
	add_css_class(s2cell, "my_opac_info_table_header");
	add_css_class(citycell, "my_opac_info_table_header");
	add_css_class(zipcell, "my_opac_info_table_header");
	add_css_class(statecell, "my_opac_info_table_header");

	s1cell.appendChild(mktext("Address 1"));
	s2cell.appendChild(mktext("Address 2"));
	citycell.appendChild(mktext("City"));
	zipcell.appendChild(mktext("Zip"));
	statecell.appendChild(mktext("State"));


	s1cell = s1row.insertCell(1);
	s2cell = s2row.insertCell(1);
	citycell = cityrow.insertCell(1);
	zipcell = ziprow.insertCell(1);
	statecell = staterow.insertCell(1);

	add_css_class(s1cell, "my_opac_profile_cell");
	add_css_class(s2cell, "my_opac_profile_cell");
	add_css_class(citycell, "my_opac_profile_cell");
	add_css_class(zipcell, "my_opac_profile_cell");
	add_css_class(statecell, "my_opac_profile_cell");


	s1cell.appendChild(mktext(addr.street1()));
	s2cell.appendChild(mktext(addr.street2()));
	citycell.appendChild(mktext(addr.city()));
	zipcell.appendChild(mktext(addr.post_code()));
	statecell.appendChild(mktext(addr.state()));

	return table;
}


MyOPACSPage.prototype.updateUsername = function() {
	var div = getById("my_opac_update_info");

	/* user clicks to close */
	if(getById("my_opac_update_usrname")) {
		removeChildren(div);
		return;
	}

	removeChildren(div);

	var ut = elem("input",{type:"text",id:"new_uname"});
	var but = elem("input",{type:"submit",value:"Update"});
	var table = elem("table");
	table.id = "my_opac_update_usrname";
	var row = table.insertRow(0);


	add_css_class(table,"my_opac_update_table");

	var c0 = row.insertCell(0);
	var c1 = row.insertCell(1);
	var c2 = row.insertCell(2);

	c0.appendChild(mktext("Enter new username: " ));
	c1.appendChild(ut);	
	c2.appendChild(but);	

	div.appendChild(elem("br"));
	div.appendChild(table);

	try{ut.focus();}catch(E){}

	/* verify looks ok, send the update request */
	var obj = this;
	but.onclick = function() {
		var uname = getById("new_uname").value;
		if(uname == null || uname == "") {
			alert("Please enter a username");
			return;
		}
		var resp = obj.user.updateUsername(uname);
		if(resp)  alert("Username updated successfully");
		else{ alert("Username update failed"); return; }
		obj.draw("profile");

	}
}

MyOPACSPage.prototype.updatePassword = function() {
	var div = getById("my_opac_update_info");

	/* user clicks to close */
	if(getById("my_opac_update_password")) {
		removeChildren(div);
		return;
	}
	removeChildren(div);

	var ut = elem("input",{type:"password",size:"15",id:"old_password"});
	var ut2 = elem("input",{type:"password",size:"15",id:"new_password_1"});
	var ut3 = elem("input",{type:"password",size:"15",id:"new_password_2"});
	var but = elem("input",{type:"submit",value:"Update"});

	var table = elem("table");
	table.id = "my_opac_update_password";
	add_css_class(table,"my_opac_update_table");

	var row = table.insertRow(0);

	var c0 = row.insertCell(0);
	var c1 = row.insertCell(1);
	var c2 = row.insertCell(2);
	var c3 = row.insertCell(3);
	var c4 = row.insertCell(4);
	var c5 = row.insertCell(5);
	var c6 = row.insertCell(6);

	c0.appendChild(mktext("Current password: " ));
	c1.appendChild(ut);	

	c2.appendChild(mktext("New password: " ));
	c3.appendChild(ut2);	

	c4.appendChild(mktext("Repeat new password: " ));
	c5.appendChild(ut3);	
	c6.appendChild(but);	

	div.appendChild(elem("br"));
	div.appendChild(table);


	try{ut.focus();}catch(E){}

	/* verify looks ok, send the update request */
	var obj = this;
	but.onclick = function() {

		var old = getById("old_password").value;
		var p1 = getById("new_password_1").value;
		var p2 = getById("new_password_2").value;

		if(!old || !p1 || !p2) {
			alert("Please fill in all fields");
			return;
		}

		if(p1 != p2) {
			alert("New passwords do not match");
			return;
		}

		var resp = obj.user.updatePassword(old, p1);
		if(resp) alert("Password updated successfully"); 
		else {alert("Password change failed"); return; }
		obj.draw("profile");
	}

}


MyOPACSPage.prototype.updateEmail = function(){
	var div = getById("my_opac_update_info");

	/* user clicks to close */
	if(getById("my_opac_update_usrname")) {
		removeChildren(div);
		return;
	}

	removeChildren(div);

	var ut = elem("input",{type:"text",id:"new_email"});
	var but = elem("input",{type:"submit",value:"Update"});
	var table = elem("table");
	table.id = "my_opac_update_usrname";
	var row = table.insertRow(0);

	add_css_class(table,"my_opac_update_table");

	var c0 = row.insertCell(0);
	var c1 = row.insertCell(1);
	var c2 = row.insertCell(2);

	c0.appendChild(mktext("Enter new email address: " ));
	c1.appendChild(ut);	
	c2.appendChild(but);	

	div.appendChild(elem("br"));
	div.appendChild(table);

	try{ut.focus();}catch(E){}

	/* verify looks ok, send the update request */
	var obj = this;
	but.onclick = function() {
		var uname = getById("new_email").value;
		if(uname == null || uname == "") {
			alert("Please enter a valid email address");
			return;
		}
		var resp = obj.user.updateEmail(uname);
		if(resp)  alert("Email updated successfully");
		else{ alert("Email update failed"); return; }
		obj.draw("profile");

	}

}

MyOPACSPage.prototype._drawHolds = function() {

	var holds = this.grabHolds();
	var table = this.infoTable;
	var row = table.insertRow(table.rows.length);

	var cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Title"));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Author"));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Format(s)"));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Pickup Location"));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Notify Email"));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_info_table_header");
	cell.appendChild(mktext("Notify Phone"));

	for( var idx = 0; idx != holds.length; idx++ ) {
		_doCallbackDance(table, holds[idx]);
	}
}

function _doCallbackDance(table, hold) {
	if(hold == null) return;
	debug("Setting holds callback with hold " + hold.id() );
	var func = function(rec) {_drawHoldsRow(table, hold, rec)};

	/* grab the record that is held */
	if(hold.hold_type() == "M")
		fetchMetaRecord(hold.target(), func);

	if(hold.hold_type() == "T")
		fetchRecord(hold.target(), func);
}



function _drawHoldsRow(table, hold, record) {

	if(record == null || record.length == 0) return;
	debug("In holds callback with hold " + hold );

	var row = table.insertRow(table.rows.length);
	var cell = row.insertCell(row.cells.length);

	add_css_class(cell, "my_opac_profile_cell");
	cell.style.width = "35%";
	cell.appendChild(mktext(record.title()));
	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_profile_cell");
	cell.appendChild(mktext(record.author()));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_profile_cell");

	var formats = hold.holdable_formats();
	if(formats == null || formats == "") /* only metarecord holds have holdable_formats */
		formats = modsFormatToMARC(record.types_of_resource()[0]);

	cell.appendChild(_mkFormatList(formats));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_profile_cell");
	cell.appendChild(mktext(findOrgUnit(hold.pickup_lib()).name()));

	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_profile_cell");
	cell.appendChild(mktext(hold.email_notify()));
	cell = row.insertCell(row.cells.length);
	add_css_class(cell, "my_opac_profile_cell");
	cell.appendChild(mktext(hold.phone_notify()));
}


function _mkFormatList(formats) {

	var div = elem("div");
	var seen = new Object();
	for( var i = 0; i!= formats.length; i++ ) {
		var form = MARCFormatToMods(formats.charAt(i));
		if(seen[form]) continue;
		div.appendChild(mkResourceImage(form));
		seen[form] = true;
	}
	return div;
}




MyOPACSPage.prototype.grabHolds = function() {
	this.user.fleshMe();
	var req = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.holds.retrieve",
		this.user.session_id,
		this.user.userObject.id() );
	req.send(true);
	return req.getResultObject();
}










/* ----------------------------------------------------------------- ========== ------------ */



MyOPACSPage.prototype.drawPersonal = function() {
	this.personalBox = new Box();
	this.personalBox.init(
		"Edit User Information", false, false);

	var obj = this;

	var uname_div = createAppElement("div");
	var uname_href = createAppElement("a");
	uname_href.onclick = function() {obj.buildUpdateUname();}
	uname_href.setAttribute("href", "javascript:void(0)");
	uname_href.appendChild(mktext("Change Username"));

	uname_div.appendChild(mktext("Username is ")); 
	var bold = createAppElement("b");
	bold.appendChild(mktext(this.user.username));
	uname_div.appendChild(bold);
	uname_div.appendChild(createAppElement("br"));
	uname_div.appendChild(uname_href);
	this.personalBox.addItem( uname_div,"edit_username");

	this.personalBox.addItem( createAppElement("hr"),"break");

	var password_href = createAppElement("a");
	password_href.setAttribute("href", "javascript:void(0)");
	password_href.onclick = function() {obj.buildUpdatePassword();}
	password_href.appendChild(mktext("Change Password"));
	this.personalBox.addItem( password_href,"edit_password");

	this.personalBox.addItem( createAppElement("hr"),"break2");

	var email_div = createAppElement("div");
	var email_href = createAppElement("a");
	email_href.onclick = function() {obj.buildUpdateEmail();}
	email_href.setAttribute("href", "javascript:void(0)");
	email_href.appendChild(mktext("Change Email Address"));

	var em = this.user.userObject.email();
	if(!em) em = "[empty]";

	email_div.appendChild(mktext("Email address is ")); 
	var bold = createAppElement("b");
	bold.appendChild(mktext(em));
	email_div.appendChild(bold);
	email_div.appendChild(createAppElement("br"));
	email_div.appendChild(email_href);
	this.personalBox.addItem( email_div,"edit_email");


	this.personal.appendChild(this.personalBox.getNode());
}


MyOPACSPage.prototype.buildUpdateEmail = function() {
	var item = this.personalBox.findByKey("edit_email");
	var node = item.getNode();

	if(node.childNodes.length > 1) {
		node.removeChild(node.childNodes[1]);
		return;
	}

	var newEmail = createAppElement("input");
	newEmail.setAttribute("type", "text");
	newEmail.id = "new_email";

	var newEmail2 = createAppElement("input");
	newEmail2.setAttribute("type", "text");
	newEmail2.id = "new_email2";

	var button = createAppElement("input");
	button.setAttribute("type", "submit");
	button.setAttribute("value", "Submit");

	var obj = this;
	button.onclick = function() { 

		var em = getById("new_email").value;
		var em2 = getById("new_email2").value;
		if(em != em2) {
			alert("Email addresses do not match");
			return;
		}
		var resp = obj.user.updateEmail(em);
		if(resp) { alert("Email updated successfully"); obj.draw();}
		else { return; }

		var node = obj.personalBox.findByKey("edit_email").getNode();
		node.removeChild(node.childNodes[1]);
	}


	var chunk = createAppElement("div");
	chunk.className = "edit_personal_active";

	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Enter New Email:"));
	chunk.appendChild(newEmail);
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Repeat New Email:"));
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(newEmail2);
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext(" "));

	var center = createAppElement("center");
	center.appendChild(button);
	chunk.appendChild(center);

	node.appendChild(chunk);
	try { newEmail.focus(); } catch(E){}

}

MyOPACSPage.prototype.buildUpdateUname = function() {
	var item = this.personalBox.findByKey("edit_username");
	var node = item.getNode();

	if(node.childNodes.length > 1) {
		node.removeChild(node.childNodes[1]);
		return;
	}

	var newName = createAppElement("input");
	newName.setAttribute("type", "text");
	newName.id = "new_uname";

	var button = createAppElement("input");
	button.setAttribute("type", "submit");
	button.setAttribute("value", "Submit");

	var obj = this;
	button.onclick = function() { 

		var resp = obj.user.updateUsername(getById("new_uname").value);
		if(resp) { alert("Username updated successfully"); obj.draw()}
		else { alert("Username update failed"); return; }

		var node = obj.personalBox.findByKey("edit_username").getNode();
		node.removeChild(node.childNodes[1]);
	}


	var chunk = createAppElement("div");
	chunk.className = "edit_personal_active";

	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Enter New Username:"));
	chunk.appendChild(newName);
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext(" "));

	var center = createAppElement("center");
	center.appendChild(button);
	chunk.appendChild(center);

	//chunk.appendChild(createAppElement("br"));
	//chunk.appendChild(createAppElement("br"));
	node.appendChild(chunk);
	try { newName.focus(); } catch(E){}
}

MyOPACSPage.prototype.buildUpdatePassword = function() {
	var item = this.personalBox.findByKey("edit_password");
	var node = item.getNode();
	if(node.childNodes.length > 1) {
		node.removeChild(node.childNodes[1]);
		return;
	}

	var oldPassword = createAppElement("input");
	oldPassword.setAttribute("type", "password");
	oldPassword.id = "old_password";

	var newPassword = createAppElement("input");
	newPassword.setAttribute("type", "password");
	newPassword.id = "new_password";

	var newPassword2 = createAppElement("input");
	newPassword2.setAttribute("type", "password");
	newPassword2.id = "new_password2";


	var button = createAppElement("input");
	button.setAttribute("type", "submit");
	button.setAttribute("value", "Submit");

	var obj = this;
	button.onclick = function() { 

		var new1 = getById("new_password").value;
		var new2 = getById("new_password2").value;
		var old	= getById("old_password").value;

		if(new1 != new2) {
			alert("Passwords do not match");
			return;
		}

		var resp = obj.user.updatePassword(old, new1);
		if(resp) { alert("Password updated successfully"); }
		else { return; }

		var node = obj.personalBox.findByKey("edit_password").getNode();
		node.removeChild(node.childNodes[1]);
	}

	var chunk = createAppElement("div");
	chunk.className = "edit_personal_active";

	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Current Password:"));
	chunk.appendChild(oldPassword);
	chunk.appendChild(createAppElement("br"));

	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Enter New Password:"));
	chunk.appendChild(newPassword);
	chunk.appendChild(createAppElement("br"));

	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(mktext("Re-Enter New Password:"));
	chunk.appendChild(newPassword2);
	chunk.appendChild(createAppElement("br"));
	chunk.appendChild(createAppElement("br"));

	chunk.appendChild(mktext(" "));

	var center = createAppElement("center");
	center.appendChild(button);
	chunk.appendChild(center);

	//chunk.appendChild(createAppElement("br"));
	node.appendChild(chunk);
	try { newPassword.focus(); } catch(E){}

}


/*
MyOPACSPage.prototype.getCheckedOut = function() {

	this.checkedOutBox = new Box();
	this.checkedOutBox.init(
		"Items Checked Out", false, false);
	this.checkedOutBox.sortByKey();


	var request = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.actor.user.checked_out",
		this.user.getSessionId() );

	var obj = this;
	request.setCompleteCallback(
		function(req) {
			obj._addCircs(req.getResultObject());
		}
	);

	request.send();
}
*/


MyOPACSPage.prototype._addCircs = function(data) {

	if(data.length < 1) {
		debug("No circs exist for this user");
		this.checkedOutBox.addItem(
			mktext("No items currently checked out") );
		return;
	}

	for( var index in data ) {

		var circ		= data[index].circ;
		var record	= data[index].record;
		var copy		= data[index].copy;


		var due = new Date(parseInt(circ.due_date() + "000")).toLocaleString();
		/* chop the 'time' portion of the date */
		due = due.replace(/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/,"");

		var title_href = createAppElement("a");
		title_href.setAttribute("href","?sub_frame=1&target=record_detail&record=" + record.doc_id() );
		title_href.setAttribute("target","_top"); /* escape to the outermost frame */
		title_href.appendChild(mktext(record.title()));

		/* grab circ lib name */
		var org = this._getOrgUnit(copy.circ_lib());
		org = org.name();

		/* for each circulation, build a small table of data */
		var table = createAppElement("table");
		this._mkCircRow(table, "Title",		title_href);
		this._mkCircRow(table, "Due Date",	mktext(due));
		this._mkCircRow(table, "Duration",	mktext(circ.duration()));
		this._mkCircRow(table, "Barcode",	mktext(copy.barcode()));
		this._mkCircRow(table, "Circulating Library", mktext(org));


		this.checkedOutBox.addItem(table);

		if(index < data.length - 1) 
			this.checkedOutBox.addItem(createAppElement("hr"));
	}

}

MyOPACSPage.prototype._mkCircRow = function(table, title, data) {
	var row = table.insertRow(table.rows.length);
	var cell = row.insertCell(row.cells.length);
	cell.appendChild(mktext(title));
	cell = row.insertCell(row.cells.length);
	cell.appendChild(data);
}


MyOPACSPage.prototype._getOrgUnit = function(org_id) {
	var request = new RemoteRequest(
		"open-ils.actor",
		"open-ils.actor.org_unit.retrieve",
		this.user.getSessionId(),
		org_id );
	request.send(true);
	return request.getResultObject();
}




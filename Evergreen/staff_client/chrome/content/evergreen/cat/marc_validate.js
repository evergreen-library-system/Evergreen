var rule_warnings = [];
var tag_seen;

function explain_marc() {
	var s = '';
	for (var w in rule_warnings) {
		s = s + rule_warnings[w];
	}
	alert(s);
}

function legend_marc() {
	var s = '';
	var rows = document.getElementById('ctrl_rows').childNodes;
	for (var r in rows) {
		if (	(typeof(rows[r]) == 'object') &&
			(rows[r].tagName == 'row') &&
			(rows[r].getAttribute('hidden') != 'true')
		) {
			var tagnumber = rows[r].firstChild.firstChild.value;
			if ((marc_rules[tagnumber])&&(marc_rules[tagnumber].desc)) {
				s = s + tagnumber + '\t' + marc_rules[tagnumber].desc + '\n';
			} else {
				s = s + tagnumber + '\n';
			}
		}
	}
	rows = document.getElementById('data_rows').childNodes;
	for (var r in rows) {
		if (	(typeof(rows[r]) == 'object') &&
			(rows[r].tagName == 'row') &&
			(rows[r].getAttribute('hidden') != 'true')
		) {
			var tagnumber = rows[r].firstChild.firstChild.value;
			if ((marc_rules[tagnumber])&&(marc_rules[tagnumber].desc)) {
				s = s + tagnumber + '\t' + marc_rules[tagnumber].desc + '\n';
			} else {
				s = s + tagnumber + '\n';
			}
		}
	}
	alert(s);

}

function handle_tag_change(ev) {
	mw.sdump('D_CAT','Entering handle_tag_change: ' + timer_elapsed('cat') + '\n');
	try {
	rule_warnings = []; disable_widgets('explain_marc');
	tag_seen = {};
	var rows = document.getElementById('ctrl_rows').childNodes;
	for (var r in rows) {
		if ((typeof(rows[r]) == 'object')&&(rows[r].tagName == 'row')) {
			test_tagnumber_rule(rows[r]);
		}
	}
	rows = document.getElementById('data_rows').childNodes;
	for (var r in rows) {
		if (	(typeof(rows[r]) == 'object') &&
			(rows[r].tagName == 'row') &&
			(rows[r].getAttribute('hidden') != 'true')
		) {
			test_tagnumber_rule(rows[r]);
			test_ind1_rule(rows[r]);
			test_ind2_rule(rows[r]);
			test_subfield_rule(rows[r]);
		}
	}
	if (rule_warnings.length > 0) { 
		enable_widgets('explain_marc'); }
	} catch(E) {
		handle_error(E);
	}
	mw.sdump('D_CAT','Exiting handle_tag_change: ' + timer_elapsed('cat') + '\n');
}

function test_tagnumber_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	try {
	var t = r.firstChild.firstChild;
	if (t.value.length > 3) { 
		t.value = t.value.substr(0,3); 
	} else if (t.value.length < 3) {
		switch(t.value.length) {
			case 2: t.value = '0' + t.value; break;
			case 1: t.value = '00' + t.value; break;
			case 0: t.value = '000'; break;
		}
	}
	removeCSSClass(t,'invalid');
	if (marc_rules[t.value]) {
		var rule = marc_rules[t.value];
		if (tag_seen[t.value]) { tag_seen[t.value]++; } else { tag_seen[t.value] = 1; }
		if ( (rule.repeat == 'NR') && (tag_seen[t.value] > 1) ) {
			addCSSClass(t,'invalid');
			var s = 'Tag ' + t.value + ' should be Non-Repeating\n';
			rule_warnings.push(s); mw.sdump('D_CAT',s);
		}
	} else if (t.value != 'LDR') {
		addCSSClass(t,'invalid');
		var s = 'Tag ' + t.value + ' is unknown.\n';
		rule_warnings.push(s); mw.sdump('D_CAT',s);
	}
	} catch(E) {
		handle_error();
	}
}

function test_ind1_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var ind1 = r.childNodes[1].firstChild;
	removeCSSClass(ind1,'invalid');
	if ((marc_rules[tagnumber]) && (marc_rules[tagnumber].ind1)) {
		var regex = '/^[' + marc_rules[tagnumber].ind1.allowed + ']$/';
		if (! ind1.value.match(eval(regex)) ) {
			addCSSClass(ind1,'invalid');
			var s = 'Tag ' + tagnumber + ' Indicator 1 should be one of these characters: "' + marc_rules[tagnumber].ind1.allowed + '"\n';
			rule_warnings.push(s); mw.sdump('D_CAT',s);
		}
	}
}

function test_ind2_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var ind2 = r.childNodes[2].firstChild;
	removeCSSClass(ind2,'invalid');
	if ((marc_rules[tagnumber]) && (marc_rules[tagnumber].ind2)) {
		var regex = '/^[' + marc_rules[tagnumber].ind2.allowed + ']$/';
		if (! ind2.value.match(eval(regex)) ) {
			addCSSClass(ind2,'invalid');
			var s = 'Tag ' + tagnumber + ' Indicator 2 should be one of these characters: "' + marc_rules[tagnumber].ind2.allowed + '"\n';
			rule_warnings.push(s); mw.sdump('D_CAT',s);
		}
	}
}

function test_subfield_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var data = r.childNodes[3].firstChild;
	removeCSSClass(data,'invalid');
	if (marc_rules[tagnumber]) {
		var datastring = data.value.replace(/^\s+/,'').replace(/\s+$/,'');
		var subf_array = datastring.split(String.fromCharCode(8225));
		if ( (subf_array[0] == '')||(subf_array[0] == null) ) {
			subf_array.shift();
		} else {
			addCSSClass(data,'invalid');
			var s = 'DEBUG: Need to add code to make an implicit subfield-a\n';
			rule_warnings.push(s); mw.sdump('D_CAT',s);
			subf_array.shift();
		}
		var subf_seen = {};
		for (var i in subf_array) {
			if ((subf_array[i]=='')||(subf_array==null)) { 
				addCSSClass(data,'invalid');
				var s = 'You have incomplete subfield delimiters.\n';
				rule_warnings.push(s); mw.sdump('D_CAT',s);
				continue;
			}
			var s_ind = subf_array[i].substr(0,1);
			if (subf_seen[s_ind]) { subf_seen[s_ind]++; } else { subf_seen[s_ind] = 1; }
			var rule = marc_rules[tagnumber][s_ind];
			if (rule) {
				if ( (rule.repeat == 'NR') && (subf_seen[s_ind]>1) ) {
					addCSSClass(data,'invalid');
					var s = 'Tag ' + tagnumber + ' subfield-' + s_ind + ' should be Non-Repeating\n';
					rule_warnings.push(s); mw.sdump('D_CAT',s);
				}
			} else {
				addCSSClass(data,'invalid');
				var s = 'Tag ' + tagnumber + ' does not have a subfield-' + s_ind + '\n';
				rule_warnings.push(s); mw.sdump('D_CAT',s);
			}
		}
	}
}

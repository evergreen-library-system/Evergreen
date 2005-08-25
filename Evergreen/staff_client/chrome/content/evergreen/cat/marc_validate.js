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
dump('1\n');
	rule_warnings = []; disable_widgets('explain_marc');
dump('2\n');
	tag_seen = {};
dump('3\n');
	var rows = document.getElementById('ctrl_rows').childNodes;
dump('4\n');
	for (var r in rows) {
dump('5\n');
		if ((typeof(rows[r]) == 'object')&&(rows[r].tagName == 'row')) {
dump('6\n');
			test_tagnumber_rule(rows[r]);
dump('7\n');
		}
dump('8\n');
	}
dump('9\n');
	rows = document.getElementById('data_rows').childNodes;
dump('10\n');
	for (var r in rows) {
dump('11\n');
		if (	(typeof(rows[r]) == 'object') &&
			(rows[r].tagName == 'row') &&
			(rows[r].getAttribute('hidden') != 'true')
		) {
dump('12\n');
			test_tagnumber_rule(rows[r]);
dump('13\n');
			test_ind1_rule(rows[r]);
dump('14\n');
			test_ind2_rule(rows[r]);
dump('15\n');
			test_subfield_rule(rows[r]);
dump('16\n');
		}
dump('17\n');
	}
dump('18\n');
	if (rule_warnings.length > 0) { 
dump('19\n');
		enable_widgets('explain_marc'); }
	} catch(E) {
dump('20\n');
		handle_error(E);
	}
dump('21\n');
	mw.sdump('D_CAT','Exiting handle_tag_change: ' + timer_elapsed('cat') + '\n');
}

function test_tagnumber_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
dump('t1\n');
	try {
dump('t2\n');
	var t = r.firstChild.firstChild;
dump('t3\n');
	if (t.value.length > 3) { 
dump('t4\n');
		t.value = t.value.substr(0,3); 
dump('t5\n');
	} else if (t.value.length < 3) {
dump('t6\n');
		switch(t.value.length) {
			case 2: t.value = '0' + t.value; break;
			case 1: t.value = '00' + t.value; break;
			case 0: t.value = '000'; break;
		}
dump('t7\n');
	}
dump('t8\n');
	removeCSSClass(t,'invalid');
dump('t9\n');
	if (marc_rules[t.value]) {
dump('t10\n');
		var rule = marc_rules[t.value];
dump('t11\n');
		if (tag_seen[t.value]) { tag_seen[t.value]++; } else { tag_seen[t.value] = 1; }
dump('t12\n');
		if ( (rule.repeat == 'NR') && (tag_seen[t.value] > 1) ) {
dump('t13\n');
			addCSSClass(t,'invalid');
dump('t14\n');
			var s = 'Tag ' + t.value + ' should be Non-Repeating\n';
dump('t15\n');
			rule_warnings.push(s); mw.sdump('D_CAT',s);
dump('t16\n');
		}
dump('t17\n');
	} else if (t.value != 'LDR') {
dump('t18\n');
		addCSSClass(t,'invalid');
dump('t19\n');
		var s = 'Tag ' + t.value + ' is unknown.\n';
dump('t20\n');
		rule_warnings.push(s); mw.sdump('D_CAT',s);
dump('t21\n');
	}
dump('t22\n');
	} catch(E) {
		dump('t23\n');
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

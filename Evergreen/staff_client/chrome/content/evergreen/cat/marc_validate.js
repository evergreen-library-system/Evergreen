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
	dump('Entering handle_tag_change: ' + timer_elapsed('cat') + '\n');
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
	if (rule_warnings.length > 0) { enable_widgets('explain_marc'); }
	dump('Exiting handle_tag_change: ' + timer_elapsed('cat') + '\n');
}

function test_tagnumber_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
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
	remove_css_class(t,'invalid');
	if (marc_rules[t.value]) {
		var rule = marc_rules[t.value];
		if (tag_seen[t.value]) { tag_seen[t.value]++; } else { tag_seen[t.value] = 1; }
		if ( (rule.repeat == 'NR') && (tag_seen[t.value] > 1) ) {
			add_css_class(t,'invalid');
			var s = 'Tag ' + t.value + ' should be Non-Repeating\n';
			rule_warnings.push(s); dump(s);
		}
	} else if (t.value != 'LDR') {
		add_css_class(t,'invalid');
		var s = 'Tag ' + t.value + ' is unknown.\n';
		rule_warnings.push(s); dump(s);
	}
}

function test_ind1_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var ind1 = r.childNodes[1].firstChild;
	remove_css_class(ind1,'invalid');
	if ((marc_rules[tagnumber]) && (marc_rules[tagnumber].ind1)) {
		var regex = '/^[' + marc_rules[tagnumber].ind1.allowed + ']$/';
		if (! ind1.value.match(eval(regex)) ) {
			add_css_class(ind1,'invalid');
			var s = 'Tag ' + tagnumber + ' Indicator 1 should be one of these characters: "' + marc_rules[tagnumber].ind1.allowed + '"\n';
			rule_warnings.push(s); dump(s);
		}
	}
}

function test_ind2_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var ind2 = r.childNodes[2].firstChild;
	remove_css_class(ind2,'invalid');
	if ((marc_rules[tagnumber]) && (marc_rules[tagnumber].ind2)) {
		var regex = '/^[' + marc_rules[tagnumber].ind2.allowed + ']$/';
		if (! ind2.value.match(eval(regex)) ) {
			add_css_class(ind2,'invalid');
			var s = 'Tag ' + tagnumber + ' Indicator 2 should be one of these characters: "' + marc_rules[tagnumber].ind2.allowed + '"\n';
			rule_warnings.push(s); dump(s);
		}
	}
}

function test_subfield_rule(r) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	var tagnumber = r.childNodes[0].firstChild.value;
	var data = r.childNodes[3].firstChild;
	remove_css_class(data,'invalid');
	if (marc_rules[tagnumber]) {
		var datastring = data.value.replace(/^\s+/,'').replace(/\s+$/,'');
		var subf_array = datastring.split(String.fromCharCode(8225));
		if ( (subf_array[0] == '')||(subf_array[0] == null) ) {
			subf_array.shift();
		} else {
			add_css_class(data,'invalid');
			var s = 'DEBUG: Need to add code to make an implicit subfield-a\n';
			rule_warnings.push(s); dump(s);
			subf_array.shift();
		}
		var subf_seen = {};
		for (var i in subf_array) {
			if ((subf_array[i]=='')||(subf_array==null)) { 
				add_css_class(data,'invalid');
				var s = 'You have incomplete subfield delimiters.\n';
				rule_warnings.push(s); dump(s);
				continue;
			}
			var s_ind = subf_array[i].substr(0,1);
			if (subf_seen[s_ind]) { subf_seen[s_ind]++; } else { subf_seen[s_ind] = 1; }
			var rule = marc_rules[tagnumber][s_ind];
			if (rule) {
				if ( (rule.repeat == 'NR') && (subf_seen[s_ind]>1) ) {
					add_css_class(data,'invalid');
					var s = 'Tag ' + tagnumber + ' subfield-' + s_ind + ' should be Non-Repeating\n';
					rule_warnings.push(s); dump(s);
				}
			} else {
				add_css_class(data,'invalid');
				var s = 'Tag ' + tagnumber + ' does not have a subfield-' + s_ind + '\n';
				rule_warnings.push(s); dump(s);
			}
		}
	}
}

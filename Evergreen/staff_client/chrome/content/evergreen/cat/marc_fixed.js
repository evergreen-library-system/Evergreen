function pad_fixed(value,field) {
	var padding = '';
	if (field == '008') {
		for (var i = value.length; i<40; i++) {
			padding = padding + ' ';
		}
	} else if (field == 'LDR') {
		for (var i = value.length; i<24; i++) {
			padding = padding + ' ';
		}
	}
	return padding;
}


function handle_fixed_change(ev) {
	mw.sdump('D_CAT','Entering handle_fixed_change\n');
	if (ev.target.tagName != 'textbox') { mw.sdump('D_CAT','early exit\n'); return; }
	var t = ev.target;
	var field = t.getAttribute('field');
	var spos = t.getAttribute('spos');
	var epos = t.getAttribute('epos');
	var size = t.getAttribute('size');
	if ( (epos - spos + 1) != size ) { 
		mw.sdump('D_CAT','Invalid fixed field DTD: field='+field+' spos='+spos+
			' epos='+epos+' size='+size+'\n');
		alert('Invalid fixed field DTD: field='+field+' spos='+spos+
			' epos='+epos+' size='+size+'\n');
	}
	if (t.value.length > size) {
		t.value = t.value.substr(0,size);
	} else if (t.value.length < size) {
		var padding = '';
		for (var i = 0; i<(size-t.value.length); i++) {
			padding = padding + ' ';
		}
		t.value = t.value + padding;
	}
	var fixed = find_textbox('ctrl_rows', field);
	//mw.sdump('D_CAT','length of fixed: ' + fixed.value.length + '\n');
	fixed.value = fixed.value + pad_fixed(fixed.value,field);
	mw.sdump('D_CAT','length of fixed: ' + fixed.value.length + '\n');

	//mw.sdump('D_CAT','field='+field+' spos='+spos+' epos='+epos+' size='+size+' t="'+t.value+'"\n');
	mw.sdump('D_CAT','replacing "'+fixed.value+'"\n');
	fixed.value = fixed.value.substr(0,spos) + t.value + fixed.value.substr(1+Number(epos));
	mw.sdump('D_CAT','     with "'+fixed.value+'"\n');
}

function find_textbox(where, field) {
	var rows = document.getElementById(where).childNodes;
	var ideal_sibling;
	for (var r in rows) {
		if (typeof(rows[r])=='object') {
			//mw.sdump('D_CAT',r + ':' + rows[r] + '\n');
			var t = rows[r].childNodes[0].firstChild;
			if (t.value == field) {
				return rows[r].childNodes[1].firstChild;
			} else if (t.value < field) {
				ideal_sibling = rows[r];
			}
		}
	}
	var new_r = build_ctrl_row('ctrl_' + new_row_id--);
	new_r.setAttribute('notempty','true');			
	new_r.setAttribute('newnode','true');
	if (ideal_sibling.nextSibling) {
		rows.insertBefore(new_r,ideal_sibling.nextSibling);
	} else {
		rows.appendChild(new_r);
	}
	new_r.childNodes[0].firstChild.value = field;
	new_r.childNodes[1].firstChild.value = padding;
	return new_r.childNodes[1].firstChild;
}

function fixed_fields_update_all(grid) {
	var g = document.getElementById(grid);
	var nl = g.getElementsByTagName('textbox');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			var t = nl[i];
			var field = t.getAttribute('field');
			var spos = t.getAttribute('spos');
			var epos = t.getAttribute('epos');
			var size = t.getAttribute('size');
			var data = find_textbox('ctrl_rows',field);
			data.value = data.value + pad_fixed(data.value,field);
			t.value = data.value.substr(spos,size);
		}
	}
}


function fixed_fields_hide_all(grid) {
	var g = document.getElementById(grid);
	var nl = g.getElementsByTagName('label');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			nl[i].setAttribute('hidden','true');
		}
	}
	nl = g.getElementsByTagName('textbox');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			nl[i].setAttribute('hidden','true');
		}
	}
}

function fixed_fields_show_all(grid) {
	var g = document.getElementById(grid);
	var nl = g.getElementsByTagName('label');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			nl[i].setAttribute('hidden','false');
		}
	}
	nl = g.getElementsByTagName('textbox');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			nl[i].setAttribute('hidden','false');
		}
	}
}

function fixed_fields_show_only(grid,attr) {
	fixed_fields_hide_all(grid);
	fixed_fields_update_all(grid);
	var g = document.getElementById(grid);
	var nl = g.getElementsByTagName('label');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			if (nl[i].getAttribute(attr) == 'true') {
				nl[i].setAttribute('hidden','false');
			}
		}
	}
	nl = g.getElementsByTagName('textbox');
	for (var i in nl) {
		if (typeof(nl[i])=='object') {
			if (nl[i].getAttribute(attr) == 'true') {
				nl[i].setAttribute('hidden','false');
			}
		}
	}
}



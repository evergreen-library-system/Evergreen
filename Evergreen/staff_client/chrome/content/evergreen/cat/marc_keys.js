function handle_keyup(ev) {
	if (ev.target.tagName != 'textbox') { return; }
	//dump('keyCode:' + ev.keyCode + ' charCode:' + ev.charCode + ' shift:' + ev.shiftKey + ' ctrl:' + ev.ctrlKey + ' meta:' + ev.metaKey + '\n');
	resizeWrapper(ev.target);
}

function handle_keypress(ev) {
	dump('keyCode:' + ev.keyCode + ' charCode:' + ev.charCode + ' shift:' + ev.shiftKey + ' ctrl:' + ev.ctrlKey + ' meta:' + ev.metaKey + '\n');
	if (ev.target.tagName != 'textbox') { return; }
	var rstatus = false;
	if (ev.charCode) {
		switch(ev.charCode) {
			case 100: 
				if (ev.ctrlKey) { /* control+d */
					rstatus = handle_key_c_d(ev);
				}
				break;
		}
	} else if (ev.keyCode) {
		switch(ev.keyCode) {
			case 13: /* enter */
			case 77: /* mac enter */
				rstatus = handle_key_enter(ev);
				break;
			case 46: 
				if (ev.ctrlKey) { /* control+del */
					rstatus = handle_key_c_del(ev);
				}
				break;
			case 9: 
				if (ev.shiftKey) { /* shift+tab */
					rstatus = navigate_col_left(ev.target,true);
				} else { /* tab */
					rstatus = navigate_col_right(ev.target,true);
				}
				break;
		}
	}
	resizeWrapper(ev.target);
	if (rstatus) {
		ev.preventDefault();
	}
	return rstatus;
}

function handle_key_c_d(ev) {
	if (ev.target.tagName != 'textbox') { return; }
	var t = ev.target;
	if ((ev.ctrlKey)&&(ev.charCode==100)&&(t.getAttribute('subfields')=='true')) {
		var n_ev = document.createEvent("KeyEvents");
		if (n_ev) { /* the best way... fake a keypress */
			n_ev.initKeyEvent("keypress", 1, 1, null, 0, 0, 0, 0, 0, 8225);
			t.inputField.dispatchEvent(n_ev);
		} else { /* this destroys the widget's undo buffer */
			var s_start = t.selectionStart; var s_end = t.selectionEnd;
			var first_half = t.value.substr(0,s_start);
			var second_half = t.value.substr(s_end);
			t.value = first_half + String.fromCharCode(8225) + second_half;
			t.setSelectionRange(s_start+1,s_start+1);
		}
		return true;
	} else {
		return false;
	}
}

function handle_key_c_del(ev) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	if (ev.target.tagName != 'textbox') { return; }
	var t = ev.target;
	var r = t.parentNode.parentNode;
	if ((ev.ctrlKey)&&(ev.keyCode==46)) {
		r.setAttribute('hidden','true');
		handle_tag_change(ev);
		if (! navigate_row_down(t,which_col_am_i(t),false) ) {
			navigate_row_up(t,which_col_am_i(t),false);
			dump("let's go up\n");
		}
		return true;
	} else {
		return false;
	}
}

var new_row_id = -1;
function handle_key_enter(ev) {
	// rows (rows) -> row (r) -> wrapper (w) -> textbox (t)
	if (ev.target.tagName != 'textbox') { return; }
	var t = ev.target; 
	if ((ev.keyCode == 13) || (ev.keyCode == 77)) {
		if (ev.ctrlKey) { // add new row
			var new_r = build_data_row('data_' + new_row_id--);
			new_r.setAttribute('notempty','true');			
			new_r.setAttribute('newnode','true');			
			var w = t.parentNode;
			var r = w.parentNode;
			var rows = r.parentNode;
			var sibling_row;
			if (ev.shiftKey) {
				sibling_row = r;
			} else {
				sibling_row = r.nextSibling;
			}
			if (sibling_row) {
				rows.insertBefore(new_r,sibling_row);
			} else {
				rows.appendChild(new_r);
			}
			var c = new_r.childNodes;
			apply_event_listeners(c,'data');
			c[1].firstChild.value = ' '; // indicator 1
			c[2].firstChild.value = ' '; // indicator 2
			c[0].firstChild.focus();
			return true;
		} else { // move to next row
			navigate_row_down(t,which_col_am_i(t),true);
			return true;
		}
	} else {
		return false;
	}
}

function which_col_am_i(t) {
	var r = t.parentNode.parentNode;
	for (var i in r.childNodes) {
		if (t == r.childNodes[i].firstChild) {
			return i;
		}
	}
}

function nextSibling_not_hidden(e) {
	var s = e.nextSibling;
	while ((s)&&(s.getAttribute('hidden')=='true')) {
		s = s.nextSibling;
	}
	return s;
}

function previousSibling_not_hidden(e) {
	var s = e.previousSibling;
	while ((s)&&(s.getAttribute('hidden')=='true')) {
		s = s.previousSibling;
	}
	return s;
}

function navigate_row_down(t,c,wrap) {
	// rows -> row (r) -> wrapper -> textbox (t)
	var r = t.parentNode.parentNode;
	var sibling_row = nextSibling_not_hidden(r);
	if (sibling_row) {
		sibling_row.childNodes[c].firstChild.focus();
		if (c == 0) {
			sibling_row.childNodes[c].firstChild.select();
		}
	} else {
		if (wrap) {
			r.parentNode.firstChild.childNodes[c].firstChild.focus();
		} else {
			return false;
		}
	}
	return true;
}

function navigate_row_up(t,c,wrap) {
	// rows -> row (r) -> wrapper -> textbox (t)
	var r = t.parentNode.parentNode;
	var sibling_row = previousSibling_not_hidden(r);
	if (sibling_row) {
		sibling_row.childNodes[c].firstChild.focus();
	} else {
		if (wrap) {
			r.parentNode.lastChild.childNodes[c].firstChild.focus();
		} else {
			return false;
		}
	}
	return true;
}

function navigate_col_left(t,wrap) {
	// rows -> row -> wrapper (w) -> textbox (t)
	var w = t.parentNode;
	var sibling_wrapper = w.previousSibling;
	if (sibling_wrapper) {
		sibling_wrapper.firstChild.focus();
		if (sibling_wrapper.parentNode.childNodes[3] != sibling_wrapper) {
			sibling_wrapper.firstChild.select();
		}
	} else {
		if (wrap) {
			return navigate_row_up(t,3,false);
		} else {
			return false;
		}
	}
	return true;
}

function navigate_col_right(t,wrap) {
	// rows -> row -> wrapper (w) -> textbox (t)
	var w = t.parentNode;
	var sibling_wrapper = w.nextSibling;
	if (sibling_wrapper) {
		sibling_wrapper.firstChild.focus();
		if (sibling_wrapper.parentNode.childNodes[3] != sibling_wrapper) {
			sibling_wrapper.firstChild.select();
		}
	} else {
		if (wrap) {
			return navigate_row_down(t,0);
		} else {
			return false;
		}
	}
	return true;
}


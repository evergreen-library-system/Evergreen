function my_init() {
	document.getElementById('search-entry-box').focus();
	dump('TESTING: cat.js: ' + mw.G['main_test_variable'] + '\n');
	populate_lib_list(
		'search-copy-count-menu',
		'search-copy-count-popup',
		mw.G.user_ou
	);
}

function search(s_type, s_loc, s_fmt, s_ord, s_term) {
	var w_type = document.getElementById(s_type);
	var w_loc = document.getElementById(s_loc);
	var w_fmt = document.getElementById(s_fmt);
	var w_term = document.getElementById(s_term);
	var w_order = document.getElementById(s_ord);
	var frame_box = document.getElementById('cat_result_box');
	while (frame_box.lastChild) { frame_box.removeChild(frame_box.lastChild); }
	switch(w_type.value) {
		case 'barcode':
			alert('Not Yet Implemented');
			break;
		case 'id':
			alert('Not Yet Implemented');
			break;
		case 'title': case 'author': case 'tcn': case 'subject':
			var frame = document.createElement('iframe');
			frame_box.appendChild(frame);
			frame.setAttribute('flex','1');
			frame.setAttribute('src','chrome://evergreen/content/cat/record_list.xul');
			frame.contentWindow.parentWindow = parentWindow;
			frame.contentWindow.search_term = w_term.value;
			frame.contentWindow.search_type = w_type.value;
			frame.contentWindow.search_location = w_loc.value;
			frame.contentWindow.search_order = w_order.value;
			frame.contentWindow.catWindow = this;
			frame.contentWindow.tabWindow = tabWindow;
			frame.contentWindow.mw = mw;
			frame.contentWindow.am_i_a_top_level_tab = false;
			dump('here ====>\n');
			frame.contentWindow.addEventListener('load',function (e) { dump('here1<==\n'); this.test_hash['hello1'] = 'boo'; }, false);
			frame.contentWindow.addEventListener('load',function (e) { dump('here2<==\n'); this.test_hash['hello2'] = 'boo'; }, false);
			break;
		case 'isbn':
			alert('Not Yet Implemented');
			break;
		case 'callnumber':
			alert('Not Yet Implemented');
			break;
		case 'all':
			alert('Not Yet Implemented');
			break;
		default:
			alert('This case is not handled: ' + w_type.value);
			break;
	}
}


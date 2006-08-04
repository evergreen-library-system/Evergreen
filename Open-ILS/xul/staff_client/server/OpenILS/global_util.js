	function ses(a) {
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		switch(a) {
			case 'authtime' :
				return data.session.authtime;
			break;
			case 'key':
			default:
				return data.session.key;
			break;
		}
	}

	function get_bool(a) {
		// Normal javascript interpretation except 'f' == false, per postgres, and 'F' == false
		// So false includes 'f', '', 0, null, and undefined
		if (a == 'f') return false;
		if (a == 'F') return false;
		if (a) return true; else return false;
	}

	function get_db_true() {
		return 't';
	}

	function get_db_false() {
		return 'f';
	}

	function copy_to_clipboard(ev) {
		try {
			netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
			var text;
			if (typeof ev == 'object') {
				if (typeof ev.target != 'undefined') {
					if (typeof ev.target.textContent != 'undefined') if (ev.target.textContent) text = ev.target.textContent;
					if (typeof ev.target.value != 'undefined') if (ev.target.value) text = ev.target.value;
				}
			} else if (typeof ev == 'string') {
				text = ev;
			}
			const gClipboardHelper = Components.classes["@mozilla.org/widget/clipboardhelper;1"]
				.getService(Components.interfaces.nsIClipboardHelper);
			gClipboardHelper.copyString(text);
			alert('Copied "'+text+'" to clipboard.');
		} catch(E) {
			alert('Clipboard action failed: ' + E);	
		}
	}


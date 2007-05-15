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

	function font_helper() {
		try {
			JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
			removeCSSClass(document.documentElement,'ALL_FONTS_LARGER');
			removeCSSClass(document.documentElement,'ALL_FONTS_SMALLER');
			removeCSSClass(document.documentElement,'ALL_FONTS_XX_SMALL');
			removeCSSClass(document.documentElement,'ALL_FONTS_X_SMALL');
			removeCSSClass(document.documentElement,'ALL_FONTS_SMALL');
			removeCSSClass(document.documentElement,'ALL_FONTS_MEDIUM');
			removeCSSClass(document.documentElement,'ALL_FONTS_LARGE');
			removeCSSClass(document.documentElement,'ALL_FONTS_X_LARGE');
			removeCSSClass(document.documentElement,'ALL_FONTS_XX_LARGE');
			addCSSClass(document.documentElement,data.global_font_adjust);
		} catch(E) {
			alert("Error with adjusting the font size: " + E);
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

	function clear_the_cache() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
			var cacheClass 		= Components.classes["@mozilla.org/network/cache-service;1"];
			var cacheService	= cacheClass.getService(Components.interfaces.nsICacheService);
			cacheService.evictEntries(Components.interfaces.nsICache.STORE_ON_DISK);
			cacheService.evictEntries(Components.interfaces.nsICache.STORE_IN_MEMORY);
		} catch(E) {
			alert('Problem clearing the cache: ' + E);
		}
	}


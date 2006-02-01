try {
	if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
	JSAN.errorLevel = "die"; // none, warn, or die
	JSAN.addRepository('..');
	JSAN.use('OpenILS.data');
	var data = new OpenILS.data(); data.init({'via':'stash'});
	var url = data.server + urls.fieldmapper;
	dump('url = ' + url + '\n');
	var js = JSAN._loadJSFromUrl( url );
	eval( js );
} catch(E) {
	alert('fmall.js: ' + E);
}

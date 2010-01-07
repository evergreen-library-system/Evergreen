var djConfig = { parseOnLoad : true };

if (location.href.match(/^.*conify\/(.+)\/global.*$/, "$1")) {
	var _url_locale = location.href.replace(/^.*conify\/(.+)\/global.*$/, "$1").replace(/_/,'-','g');

	if (_url_locale) djConfig.locale = _url_locale.toLowerCase();

} else {
	var _url_locale = '<!--#echo var="locale"-->';
	if (_url_locale != '(none)') djConfig.locale = _url_locale.toLowerCase();
}

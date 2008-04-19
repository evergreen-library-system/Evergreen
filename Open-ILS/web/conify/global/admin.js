var djConfig = { parseOnLoad : true };

var _url_locale = location.href.replace(/^.*conify\/(.+)\/global.*$/, "$1").toLowerCase().replace(/-/,'_');
if (_url_locale) djConfig.locale = _url_locale;
else djConfig.locale = '<!--#echo var="locale"-->';


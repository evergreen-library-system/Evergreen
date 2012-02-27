dump('entering util/mozilla.js\n');

const Cc = Components.classes;
const Ci = Components.interfaces;

if (typeof util == 'undefined') var util = {};
util.mozilla = {};

util.mozilla.EXPORT_OK    = [ 
    'chromeRegistry', 'languages', 'regions', 'prefs'
];
util.mozilla.EXPORT_TAGS    = { ':all' : util.mozilla.EXPORT_OK };

util.mozilla.chromeRegistry = function() {
    try {

        return Cc['@mozilla.org/chrome/chrome-registry;1'].getService(Ci['nsIToolkitChromeRegistry']);

    } catch(E) {
        alert("FIXME: util.mozilla.reloadChrome() = " + E);
    }
}

util.mozilla.languages = function() {
    try {

        var stringBundles = Cc['@mozilla.org/intl/stringbundle;1'].getService(Ci['nsIStringBundleService']);
        return stringBundles.createBundle('chrome://global/locale/languageNames.properties');

    } catch(E) {
        alert("FIXME: util.mozilla.reloadChrome() = " + E);
    }
}

util.mozilla.regions = function() {
    try {

        var stringBundles = Cc['@mozilla.org/intl/stringbundle;1'].getService(Ci['nsIStringBundleService']);
        return stringBundles.createBundle('chrome://global/locale/regionNames.properties');

    } catch(E) {
        alert("FIXME: util.mozilla.reloadChrome() = " + E);
    }
}

util.mozilla.prefs = function() {
    try {

        return Cc['@mozilla.org/preferences-service;1'].getService(Ci['nsIPrefBranch']);

    } catch(E) {
        alert("FIXME: util.mozilla.reloadChrome() = " + E);
    }
}

util.mozilla.change_locale = function( locale ) {
    try {
        var current_locale = 'en-US';
        try { current_locale = util.mozilla.prefs().getCharPref('general.useragent.locale'); } catch(E) { alert('util.locale.change, prefs() = ' + E); }
        if (locale != current_locale) {
            util.mozilla.prefs().setCharPref('general.useragent.locale',locale);
            util.mozilla.prefs().setCharPref('intl.accept_languages',locale);
            util.mozilla.chromeRegistry().reloadChrome();
        }

    } catch(E) {
        alert('FIXME: util.mozilla.change_locale( "' + locale + ") = " + E);
    }
}


dump('exiting util/mozilla.js\n');

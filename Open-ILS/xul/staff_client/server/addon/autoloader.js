dump('entering addon/autoloader.js\n');
// vim:noet:sw=4:ts=4:

/*
    Usage example:

    JSAN.use('addon.autoloader');
    var autoloader = new addon.autoloader({'pref':'oils.addon.autoload.list'});
    autoloader.list();
    autoloader.objects();
*/

if (typeof addon == 'undefined') addon = {};
addon.autoloader = function (params) {
    try {
        dump('addon: autoloader() constructor at ' + location.href + '\n');
        if (typeof params == 'undefined') {
            params = { 'pref' : 'oils.addon.autoload.list' };
        }

        const Cc = Components.classes;
        const Ci = Components.interfaces;
        const prefs_Cc = '@mozilla.org/preferences-service;1';
        this.prefs = Cc[prefs_Cc].getService(Ci['nsIPrefBranch']);

        this._list = this.list(params);

        this._hash = this.load( this._list, params );

        return this;

    } catch(E) {
        dump('addon: Error in autoloader(): ' + E + '\n');
    }
}

addon.autoloader.prototype = {
    'list' : function(params) {
        var list = [];
        if (typeof params == 'undefined') {
            list = this._list;
        }
        if (params.pref) {
            if (this.prefs.prefHasUserValue(params.pref)) {
                list = list.concat(
                    JSON2js(
                        this.prefs.getCharPref(
                            params.pref
                        )
                    )
                );
            }
        }
        if (params.list) {
            list = list.concat( params.list );
        }
        return list;
    },
    'objects' : function() {
        return this._hash;
    },
    'load' : function(list,params) {
        dump('addon: autloader load()\n');
        var objs = {};
        for (var i = 0; i < list.length; i++) {
            try {
                dump('addon: autloader load() -> ' + list[i] + '\n');
                JSAN.use('addon.'+list[i]);
                objs[list[i]] = new addon[list[i]](params);
            } catch(E) {
                dump('addon: autloader load() -> ' + list[i] + ' error: ' + E + '\n');
                objs[list[i]] = function(e){return e;}(E);
            }
        }
        return objs;
    }
}


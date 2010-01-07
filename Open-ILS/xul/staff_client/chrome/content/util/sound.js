dump('entering util/sound.js\n');

if (typeof util == 'undefined') util = {};
util.sound = function () {

    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        var SOUNDContractID = "@mozilla.org/sound;1";
        var SOUNDIID        = Components.interfaces.nsISound;
        this.SOUND          = Components.classes[SOUNDContractID].createInstance(SOUNDIID);

    } catch(E) {
        dump('util.sound constructor: ' + E + '\n');
    }

    return this;
};

util.sound.prototype = {

    'xp_url_init' : function (aURL) {
        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            var URLContractID   = "@mozilla.org/network/standard-url;1";
            var URLIID          = Components.classes[URLContractID].createInstance( );
            var URL             = URLIID.QueryInterface(Components.interfaces.nsIURL);
            if (aURL) {
                URL.spec = aURL;
            }
            return URL;
        } catch(E) {
            alert('xp_url_init(): ' + E);
        }
    },

    'play_url' : function(url) {

        var obj = this;
        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var url2 = obj.xp_url_init( data.server + url );
            dump('url = ' + url2 + '\n');
            if (typeof data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') obj.SOUND.play( url2 );
        } catch(E) {
            try { if (data.no_sound == 'undefined' || data.no_sound == false || data.no_sound == 'false') obj.SOUND.beep(); } catch(F) { 
                dump('beep(): ' + F + '\n');
            }
            dump('play_url(): ' + E + '\n');
        }

    },

    'good' : function(e){
        this.play_url( urls.AUDIO_GOOD_SOUND );
    },

    'bad' : function(e){
        this.play_url( urls.AUDIO_BAD_SOUND );
    },

    'horrible' : function(e){
        this.play_url( urls.AUDIO_HORRIBLE_SOUND );
    },

    'circ_good' : function(e){
        this.play_url( urls.AUDIO_CIRC_GOOD_SOUND );
    },

    'circ_bad' : function(e){
        this.play_url( urls.AUDIO_CIRC_BAD_SOUND );
    },
}

dump('exiting util/sound.js\n');

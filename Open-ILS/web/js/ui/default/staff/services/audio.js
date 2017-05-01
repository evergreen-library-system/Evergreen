/**
 * Core Service - egAudio
 *
 * Plays audio files by key name.  Each sound uses a dot-path to indicate 
 * the sound.  
 *
 * For example:
 * sound => 'warning.checkout.no_item'
 * URLs are tested in the following order until a valid audio file is found
 * or no other paths are left to check.
 *
 * /audio/notifications/warning/checkout/not_found.wav
 * /audio/notifications/warning/checkout.wav
 * /audio/notifications/warning.wav
 *
 * TODO: move audio file base path settings to the template 
 * for configurability?
 *
 * Files are only played when sounds are configured to play via 
 * workstation settings.
 */

angular.module('egCoreMod')

.factory('egAudio', ['$q','egHatch', function($q, egHatch) {

    var service = {
        url_cache : {}, // map key names to audio file URLs
        base_url : '/audio/notifications/'
    };

    /** 
     * Play the sound found at the requested string path.  'path' is a 
     * key name which maps to an audio file URL.
     */
    service.play = function(path) {
        if (!path) return;
        service.play_url(path, path);
    }

    service.play_url = function(path, orig_path) {
        console.log('audio: play_url('+path+','+orig_path+')');

        egHatch.getItem('eg.audio.disable').then(function(audio_disabled) {
            if (!audio_disabled) {
        
                var url = service.url_cache[path] || 
                    service.base_url + path.replace(/\./g, '/') + '.wav';

                var player = new Audio(url);

                player.onloadeddata = function() {
                    service.url_cache[orig_path] = url;
                    player.play();
                    console.log('audio: ' + url);
                };

                if (service.url_cache[path]) {
                    // when serving from the cache, avoid secondary URL lookups.
                    return;
                }

                player.onerror = function() {
                    // Unable to play path at the requested URL.
            
                    if (!path.match(/\./)) {
                        // all fall-through options have been exhausted.
                        // No path to play.
                        console.warn(
                            "No suitable URL found for path '" + orig_path + "'");
                        return;
                    }

                    // Fall through to the next (more generic) option
                    path = path.replace(/\.[^\.]+$/, '');
                    service.play_url(path, orig_path);
                }
            }
        });
    }

    return service;
}]);


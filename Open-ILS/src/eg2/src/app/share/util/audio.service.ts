/**
 * Plays audio files (alerts, generally) by key name.  Each sound uses a
 * dot-path to indicate  the sound.
 *
 * For example:
 *
 * this.audio.play('warning.checkout.no_item');
 *
 * URLs are tested in the following order until an audio file is found
 * or no other paths are left to check.
 *
 * /audio/notifications/warning/checkout/not_found.wav
 * /audio/notifications/warning/checkout.wav
 * /audio/notifications/warning.wav
 *
 * Files are only played when sounds are configured to play via
 * workstation settings.
 */
import {Injectable, EventEmitter} from '@angular/core';
import {ServerStoreService} from '@eg/core/server-store.service';
const AUDIO_BASE_URL = '/audio/notifications/';

@Injectable()
export class AudioService {

    // map of requested audio path to resolved path
    private urlCache: {[path: string]: string} = {};

    constructor(private store: ServerStoreService) {}

    play(path: string): void {
        if (path) {
            this.playUrl(path, path);
        }
    }

    playUrl(path: string, origPath: string): void {
        // console.debug(`audio: playUrl(${path}, ${origPath})`);

        this.store.getItem('eg.audio.disable').then(audioDisabled => {
            if (audioDisabled) { return; }

            const url = this.urlCache[path] ||
                AUDIO_BASE_URL + path.replace(/\./g, '/') + '.wav';

            const player = new Audio(url);

            player.onloadeddata = () => {
                this.urlCache[origPath] = url;
                player.play();
                console.debug(`audio: ${url}`);
            };

            if (this.urlCache[path]) {
                // when serving from the cache, avoid secondary URL lookups.
                return;
            }

            player.onerror = () => {
                // Unable to play path at the requested URL.

                if (!path.match(/\./)) {
                    // all fall-through options have been exhausted.
                    // No path to play.
                    console.warn(
                        `No suitable URL found for path "${origPath}"`);
                    return;
                }

                // Fall through to the next (more generic) option
                path = path.replace(/\.[^\.]+$/, '');
                this.playUrl(path, origPath);
            };
        });
    }
}



/**
 * Create and consume BroadcastChannel broadcasts
 */
import {Injectable, EventEmitter} from '@angular/core';
import {empty} from 'rxjs';

interface BroadcastSub {
    channel: any; // BroadcastChannel
    emitter: EventEmitter<any>;
}

@Injectable()
export class BroadcastService {

    subscriptions: {[key: string]: BroadcastSub} = {};

    noOpEmitter = new EventEmitter<any>();

    listen(key: string): EventEmitter<any> {
        if (typeof BroadcastChannel === 'undefined') {
            return this.noOpEmitter;
        }

        if (this.subscriptions[key]) {
            return this.subscriptions[key].emitter;
        }

        const emitter = new EventEmitter<any>();
        const channel = new BroadcastChannel(key);

        channel.onmessage = (e) => {
            console.debug('Broadcast received', e.data);
            emitter.emit(e.data);
        };

        this.subscriptions[key] = {
            channel: channel,
            emitter: emitter
        };

        return emitter;
    }

    broadcast(key: string, value: any) {
        if (typeof BroadcastChannel === 'undefined') { return; }

        if (this.subscriptions[key]) {
            this.subscriptions[key].channel.postMessage(value);

        } else {

            // One time use channel
            const channel = new BroadcastChannel(key);
            channel.postMessage(value);
            channel.close();
        }
    }

    close(key: string) {
        if (typeof BroadcastChannel === 'undefined') { return; }

        if (this.subscriptions[key]) {
            this.subscriptions[key].channel.close();
            this.subscriptions[key].emitter.complete();
            delete this.subscriptions[key];
        }
    }
}


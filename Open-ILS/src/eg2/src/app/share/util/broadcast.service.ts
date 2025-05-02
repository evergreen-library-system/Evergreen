/* eslint-disable max-len */
/**
 * Create and consume BroadcastChannel broadcasts
 */
import {Injectable, EventEmitter} from '@angular/core';

interface BroadcastSub {
    channel: any; // BroadcastChannel
    emitter: EventEmitter<any>;
}

@Injectable({
    providedIn: 'root'
})
export class BroadcastService {

    private instanceId = crypto.randomUUID();

    subscriptions: {[key: string]: BroadcastSub} = {};

    noOpEmitter = new EventEmitter<any>();

    listen(key: string): EventEmitter<any> {
        console.debug('BroadcastService('+this.instanceId+'), listen: key', key);
        if (typeof BroadcastChannel === 'undefined') {
            return this.noOpEmitter;
        }

        if (this.subscriptions[key]) {
            return this.subscriptions[key].emitter;
        }

        const emitter = new EventEmitter<any>();
        const channel = new BroadcastChannel(key);

        channel.onmessage = (e) => {
            console.debug('BroadcastService('+this.instanceId+'), Broadcast received: key, data', key, e.data);
            emitter.emit(e.data);
        };

        this.subscriptions[key] = {
            channel: channel,
            emitter: emitter
        };

        return emitter;
    }

    broadcast(key: string, value: any) {
        console.debug('BroadcastService(' + this.instanceId + '), broadcast: key, value', key, value);
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
        console.debug('BroadcastService(' + this.instanceId + '), close: key', key);
        if (typeof BroadcastChannel === 'undefined') { return; }

        if (this.subscriptions[key]) {
            this.subscriptions[key].channel.close();
            this.subscriptions[key].emitter.complete();
            delete this.subscriptions[key];
        }
    }

    listenIgnoreSameSource(key: string): EventEmitter<any> {
        if (typeof BroadcastChannel === 'undefined') {
            return this.noOpEmitter;
        }

        const emitter = new EventEmitter<any>();

        this.listen(key)
            .subscribe(data => {
                // Only emit if from different source
                if (data?.sourceId !== this.instanceId) {
                    console.debug('BroadcastService(' + this.instanceId + '), Broadcast received from different source: key, data', key, data);
                    emitter.emit(data);
                } else {
                    console.debug('BroadcastService(' + this.instanceId + '), Broadcast received and ignored same source message: key, data', key, data);
                }
            });

        return emitter;
    }

    broadcastWithSource(key: string, value: any) {
        if (typeof BroadcastChannel === 'undefined') { return; }

        const valueWithSource = {
            ...value,
            sourceId: this.instanceId
        };

        console.debug('broadcastWithSource(' + this.instanceId + '): key, value', key, valueWithSource);
        this.broadcast(key, valueWithSource);
    }
}


/* eslint-disable eqeqeq, no-shadow */
import {Injectable} from '@angular/core';

export type PrintContext = 'default' | 'receipt' | 'label' | 'mail' | 'offline';

export const PRINT_CONTEXTS: PrintContext[] = [
    'default',
    'receipt',
    'label',
    'mail',
    'offline'
];

export interface PrintConfig {
    context: PrintContext;
    printer: string;
    autoMargins: boolean;
    allPages: boolean;
    pageRanges: number[];
}

export class HatchMessage {
    msgid: number;
    resolver: (HatchMessage) => void; // promise resolver
    rejector: (HatchMessage) => void; // promise rejector
    status: number;
    message: string; // error message
    from: string;
    action: string;
    settings: any;
    content: string;
    // Response from Hatch.
    response: any;
    contentType: string;
    showDialog: boolean;

    constructor(hash: any) {
        if (hash) {
            Object.keys(hash).forEach(key => this[key] = hash[key]);
        }
    }
}

@Injectable({providedIn: 'root'})
export class HatchService {

    isAvailable: boolean;
    msgId: number;
    messages: {[msgid: number]: HatchMessage};
    printers: any[];

    constructor() {
        this.isAvailable = null;
        this.messages = {};
        this.msgId = 1;
    }

    connect(): boolean {

        if (this.isAvailable !== null) {
            return this.isAvailable;
        }

        // When the Hatch extension loads, it tacks an attribute onto
        // the top-level documentElement to indicate it's available.
        if (!window.document.documentElement.getAttribute('hatch-is-open')) {
            console.debug('Could not connect to Hatch');
            return this.isAvailable = false;
        }

        window.addEventListener('message', event => {

            // We only accept messages from our own content script.
            if (event.source !== window) { return; }

            // We only care about messages from the Hatch extension.
            if (event.data && event.data.from === 'extension') {

                // Avoid logging full Hatch responses. they can get large.
                console.debug(
                    `Hatch responded to message ID ${event.data.msgid}`);

                this.handleResponse(event.data);
            }
        });

        return this.isAvailable = true;
    }

    // Send a request from the browser to Hatch.
    sendRequest(msg: HatchMessage): Promise<HatchMessage> {
        if (this.isAvailable === false) {
            return Promise.reject('Hatch is not connected');
        }

        msg.msgid = this.msgId++;
        msg.from = 'page';
        this.messages[msg.msgid] = msg;
        window.postMessage(msg, window.location.origin);

        return new Promise((resolve, reject) => {
            msg.resolver = resolve;
            msg.rejector = reject;
        });
    }

    // Handle the data sent back to the browser from Hatch.
    handleResponse(data: any) {

        const msg = this.messages[data.msgid];
        if (!msg) {
            console.warn(`No Hatch request found with ID ${data.msgid}`);
            return;
        }

        delete this.messages[data.msgid];
        msg.response = data.content;
        msg.message = data.message;
        msg.status = Number(data.status);

        // eslint-disable-next-line no-magic-numbers
        if (msg.status === 200) {
            msg.resolver(msg);
        } else {
            console.error(`Hatch request returned status ${msg.status}`, msg);
            msg.rejector(msg);
        }
    }

    // Returns promise of null if Hatch is not available.
    hostname(): Promise<string> {
        const msg = new HatchMessage({action: 'hostname'});
        return this.sendRequest(msg).then(
            (m: HatchMessage) => m.response,
            (err) => null
        );
    }

    getItem(key: string): Promise<any> {
        const msg = new HatchMessage({action: 'get', key: key});
        return this.sendRequest(msg).then((m: HatchMessage) => m.response);
    }

    setItem(key: string, val: any): Promise<any> {
        const msg = new HatchMessage({action: 'set', key: key, content: val});
        return this.sendRequest(msg).then((m: HatchMessage) => m.response);
    }

    removeItem(key: string): Promise<any> {
        const msg = new HatchMessage({action: 'remove', key: key});
        return this.sendRequest(msg).then((m: HatchMessage) => m.response);
    }

    getPrinterOptions(name: string): Promise<any> {
        if (name === 'hatch_file_writer' || name === 'hatch_browser_printing' || name == '') {
            return Promise.resolve({});
        }
        const msg = new HatchMessage({action: 'printer-options', printer: name});
        return this.sendRequest(msg).then((m: HatchMessage) => m.response);
    }

    getPrinters(): Promise<any[]> {
        if (this.printers) { return Promise.resolve(this.printers); }

        this.printers = [
            {name: 'hatch_file_writer'},
            {name: 'hatch_browser_printing'}
        ];

        const msg = new HatchMessage({action: 'printers'});
        return this.sendRequest(msg).then((m: HatchMessage) => m.response)
            .then(
                printers => {
                    this.printers =
                    printers.sort((p1, p2) => p1.name < p2.name ? -1 : 1)
                        .concat(this.printers);

                    return this.printers;
                },
                err => {
                    return this.printers;
                }
            );
    }
}


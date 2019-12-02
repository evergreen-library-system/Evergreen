import {Injectable} from '@angular/core';

/** Service to relay requests to/from our IndexedDB shared worker */

// TODO: move to a more generic location.
const WORKER_URL = '/js/ui/default/staff/offline-db-worker.js';

// Tell TS about SharedWorkers
// https://stackoverflow.com/questions/13296549/typescript-enhanced-sharedworker-portmessage-channel-contracts
interface SharedWorker extends AbstractWorker {
    port: MessagePort;
}

declare var SharedWorker: {
    prototype: SharedWorker;
    new (scriptUrl: any, name?: any): SharedWorker;
};
// ---

// Requests in flight to the shared worker
interface ActiveRequest {
   id: number;
   resolve(response: any): any;
   reject(error: any): any;
}

// Shared worker request structure.  This is the request that's
// relayed to the shared worker.
// DbStoreRequest.id === ActiveRequest.id
interface DbStoreRequest {
    schema: string;
    action: string;
    field?: string;
    value?: any;
    table?: string;
    rows?: any[];
    id?: number;
}

// Expected response structure from the shared worker.
// Note callers only recive the 'result' content, which may
// be anything.
interface DbStoreResponse {
    status: string;
    result: any;
    error?: string;
    id?: number;
}

@Injectable({providedIn: 'root'})
export class DbStoreService {

    autoId = 0; // each request gets a unique id.
    cannotConnect: boolean;

    activeRequests: {[id: number]: ActiveRequest} = {};

    // Schemas we should connect to
    activeSchemas: string[] = ['cache']; // add 'offline' in the offline UI

    // Schemas we are in the process of connecting to
    schemasInProgress: {[schema: string]: Promise<any>} = {};

    // Schemas we have successfully connected to
    schemasConnected: {[schema: string]: boolean} = {};

    worker: SharedWorker = null;

    constructor() {}

    private connectToWorker() {
        if (this.worker || this.cannotConnect) { return; }

        try {
            this.worker = new SharedWorker(WORKER_URL);
        } catch (E) {
            console.warn('SharedWorker() not supported', E);
            this.cannotConnect = true;
            return;
        }

        this.worker.onerror = err => {
            this.cannotConnect = true;
            console.error('Cannot connect to DB shared worker', err);
        };

        // List for responses and resolve the matching pending request.
        this.worker.port.addEventListener(
            'message', evt => this.handleMessage(evt));

        this.worker.port.start();
    }

    private handleMessage(evt: MessageEvent) {
        const response: DbStoreResponse = evt.data as DbStoreResponse;
        const reqId = response.id;
        const req = this.activeRequests[reqId];

        if (!req) {
            console.error('Recieved response for unknown request', reqId);
            return;
        }

        // Request is no longer active.
        delete this.activeRequests[reqId];

        if (response.status === 'OK') {
            req.resolve(response.result);
        } else {
            console.error('worker request failed with', response.error);
            req.reject(response.error);
        }
    }

    // Send a request to the web worker and register the request
    // for future resolution.  Store the request ID in the request
    // arguments, so it's included in the response, and in the
    // activeRequests list for linking.
    private relayRequest(req: DbStoreRequest): Promise<any> {
        return new Promise((resolve, reject) => {
            const id = req.id = this.autoId++;
            this.activeRequests[id] = {id: id, resolve: resolve, reject: reject};
            this.worker.port.postMessage(req);
        });
    }

    // Connect to all active schemas, requesting each be created
    // when necessary.
    private connectToSchemas(): Promise<any> {
        const promises = [];

        this.activeSchemas.forEach(schema =>
            promises.push(this.connectToOneSchema(schema)));

        return Promise.all(promises).then(
            _ => {},
            err => this.cannotConnect = true
        );
    }

    private connectToOneSchema(schema: string): Promise<any> {

        if (this.schemasConnected[schema]) {
            return Promise.resolve();
        }

        if (this.schemasInProgress[schema]) {
            return this.schemasInProgress[schema];
        }

        const promise = new Promise((resolve, reject) => {

            this.relayRequest({schema: schema, action: 'createSchema'})

            .then(_ =>
                this.relayRequest({schema: schema, action: 'connect'}))

            .then(
                _ => {
                    this.schemasConnected[schema] = true;
                    delete this.schemasInProgress[schema];
                    resolve();
                },
                err => reject(err)
            );
        });

        return this.schemasInProgress[schema] = promise;
    }

    request(req: DbStoreRequest): Promise<any> {

        // NO-OP if we're already connected.
        this.connectToWorker();

        // If we are unable to connect, it means we are in an
        // environment that does not support shared workers.
        // Treat all requests as a NO-OP.
        if (this.cannotConnect) { return Promise.resolve(); }

        return this.connectToSchemas().then(_ => this.relayRequest(req));
    }
}



import {Injectable} from '@angular/core';

/** Service to relay requests to/from our IndexedDB shared worker
 *  Beware requests will be rejected when SharedWorker's are not supported.

    this.db.request(
        schema: 'cache',
        table: 'Setting',
        action: 'selectWhereIn',
        field: 'name',
        value: ['foo']
    ).then(value => console.log('my value', value)
    ).catch(_ => console.log('SharedWorker's not supported));

 */

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

    // Returns true if connection is successful, false otherwise
    private connectToWorker(): boolean {
        if (this.worker) { return true; }
        if (this.cannotConnect) { return false; }

        try {
            this.worker = new SharedWorker(WORKER_URL);
        } catch (E) {
            console.warn('SharedWorker() not supported', E);
            this.cannotConnect = true;
            return false;
        }

        this.worker.onerror = err => {
            this.cannotConnect = true;
            console.error('Cannot connect to DB shared worker', err);
        };

        // List for responses and resolve the matching pending request.
        this.worker.port.addEventListener(
            'message', evt => this.handleMessage(evt));

        this.worker.port.start();
        return true;
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
    // Returns a rejected promise if shared workers are not supported.
    private relayRequest(req: DbStoreRequest): Promise<any> {

        if (!this.connectToWorker()) {
            return Promise.reject('Shared Workers not supported');
        }

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

    // Request may be rejected if SharedWorker's are not supported.
    // All calls to this method should include an error handler in
    // the .then() or a .cache() handler after the .then().
    request(req: DbStoreRequest): Promise<any> {
        return this.connectToSchemas().then(_ => this.relayRequest(req));
    }
}



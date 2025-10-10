/* eslint-disable no-shadow, no-var */
import {Injectable} from '@angular/core';
import {Observable, Observer} from 'rxjs';
import {IdlService, IdlObject} from './idl.service';
import {NetService, NetRequest} from './net.service';
import {AuthService} from './auth.service';
import {StoreService} from './store.service';

// Externally defined.  Used here for debugging.
declare var js2JSON: (jsThing: any) => string;
declare var OpenSRF: any; // creating sessions

interface PcrudReqOps {
    authoritative?: boolean;
    anonymous?: boolean;
    idlist?: boolean;
    count_only?: boolean;
    atomic?: boolean;
    // If true, link-type fields which link to a class that defines a
    // selector will be fleshed with the linked value.  This affects
    // retrieve(), retrieveAll(), and search() calls.
    fleshSelectors?: boolean;
}

// For for documentation purposes.
type PcrudResponse = any;

export class PcrudContext {

    static verboseLogging = true; //
    static identGenerator = 0; // for debug logging

    private ident: number;
    private authoritative: boolean;
    private xactCloseMode: string;
    private cudIdx: number;
    private cudAction: string;
    private cudLast: PcrudResponse;
    private cudList: IdlObject[];

    private idl: IdlService;
    private net: NetService;
    private auth: AuthService;

    // Tracks nested CUD actions
    cudObserver: Observer<PcrudResponse>;

    session: any; // OpenSRF.ClientSession

    constructor( // passed in by parent service -- not injected
        egIdl: IdlService,
        egNet: NetService,
        egAuth: AuthService
    ) {
        this.idl = egIdl;
        this.net = egNet;
        this.auth = egAuth;
        this.xactCloseMode = 'rollback';
        this.ident = PcrudContext.identGenerator++;
        this.session = new OpenSRF.ClientSession('open-ils.pcrud');
    }

    toString(): string {
        return '[PCRUDContext ' + this.ident + ']';
    }

    log(msg: string): void {
        if (PcrudContext.verboseLogging) {
            console.debug(this + ': ' + msg);
        }
    }

    err(msg: string): void {
        console.error(this + ': ' + msg);
    }

    token(reqOps?: PcrudReqOps): string {
        return (reqOps && reqOps.anonymous) ?
            'ANONYMOUS' : this.auth.token();
    }

    connect(): Promise<PcrudContext> {
        this.log('connect');
        return new Promise( (resolve, reject) => {
            this.session.connect({
                onconnect : () => { resolve(this); }
            });
        });
    }

    disconnect(): void {
        this.log('disconnect');
        this.session.disconnect();
    }

    // Adds "flesh" logic to retrieve linked values for all fields
    // that link to a class which defines a selector field.
    applySelectorFleshing(fmClass: string, pcrudOps: any) {
        pcrudOps = pcrudOps || {};

        if (!pcrudOps.flesh) {
            pcrudOps.flesh = 1;
        }

        if (!pcrudOps.flesh_fields) {
            pcrudOps.flesh_fields = {};
        }

        this.idl.classes[fmClass].fields
            .filter(f =>
                f.datatype === 'link' && (
                    f.reltype === 'has_a' || f.reltype === 'might_have'
                )
            ).forEach(field => {

                const selector = this.idl.getLinkSelector(fmClass, field.name);
                if (!selector) { return; }

                if (field.map) {
                // For mapped fields, we only want to auto-flesh them
                // if both steps along the path are single-row fleshers.

                    const mapClass = field['class'];
                    const mapField = field.map;
                    const def = this.idl.classes[mapClass].field_map[mapField];

                    if (!(def.reltype === 'has_a' ||
                      def.reltype === 'might_have')) {
                    // Field maps to a remote field which may contain
                    // multiple rows.  Skip it.
                        return;
                    }
                }

                if (!pcrudOps.flesh_fields[fmClass]) {
                    pcrudOps.flesh_fields[fmClass] = [];
                }

                if (pcrudOps.flesh_fields[fmClass].indexOf(field.name) < 0) {
                    pcrudOps.flesh_fields[fmClass].push(field.name);
                }
            });
    }

    retrieve(fmClass: string, pkey: Number | string,
        pcrudOps?: any, reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        reqOps = reqOps || {};
        this.authoritative = reqOps.authoritative || false;
        if (reqOps.fleshSelectors) {
            this.applySelectorFleshing(fmClass, pcrudOps);
        }
        return this.dispatch(
            `open-ils.pcrud.retrieve.${fmClass}`,
            [this.token(reqOps), pkey, pcrudOps]);
    }

    retrieveAll(fmClass: string, pcrudOps?: any,
        reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        const search = {};
        search[this.idl.classes[fmClass].pkey] = {'!=' : null};
        return this.search(fmClass, search, pcrudOps, reqOps);
    }

    search(fmClass: string, search: any,
        pcrudOps?: any, reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        reqOps = reqOps || {};
        this.authoritative = reqOps.authoritative || false;

        let returnType = reqOps.idlist ? 'id_list' : 'search';
        if (reqOps.count_only) {
            returnType = 'count';
            reqOps.atomic = reqOps.fleshSelectors = false;
        }

        let method = `open-ils.pcrud.${returnType}.${fmClass}`;

        if (reqOps.atomic) { method += '.atomic'; }

        if (reqOps.fleshSelectors) {
            this.applySelectorFleshing(fmClass, pcrudOps);
        }

        return this.dispatch(method, [this.token(reqOps), search, pcrudOps]);
    }

    create(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.cud('create', list);
    }
    update(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.cud('update', list);
    }
    remove(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.cud('delete', list);
    }
    autoApply(list: IdlObject | IdlObject[]): Observable<PcrudResponse> { // RENAMED
        return this.cud('auto',   list);
    }

    xactClose(): Observable<PcrudResponse> {
        return this.sendRequest(
            'open-ils.pcrud.transaction.' + this.xactCloseMode,
            [this.token()]
        );
    }

    xactBegin(): Observable<PcrudResponse> {
        return this.sendRequest(
            'open-ils.pcrud.transaction.begin', [this.token()]
        );
    }

    private dispatch(method: string, params: any[]): Observable<PcrudResponse> {
        if (this.authoritative && PcrudService.useAuthoritative) {
            return this.wrapXact(() => {
                return this.sendRequest(method, params);
            });
        } else {
            return this.sendRequest(method, params);
        }
    }


    // => connect
    // => xact_begin
    // => action
    // => xact_close(commit/rollback)
    // => disconnect
    wrapXact(mainFunc: () => Observable<PcrudResponse>): Observable<PcrudResponse> {
        return new Observable(observer => {

            // 1. connect
            this.connect()

            // 2. start the transaction
                .then(() => this.xactBegin().toPromise())

            // 3. execute the main body
                .then(() => {

                    mainFunc().subscribe(
                        { next: res => observer.next(res), error: (err: unknown) => observer.error(err), complete: ()  => {
                            this.xactClose().toPromise().then(
                                ok => {
                                // 5. disconnect
                                    this.disconnect();
                                    // 6. all done
                                    observer.complete();
                                },
                                // xact close error
                                err => observer.error(err)
                            );
                        } }
                    );
                });
        });
    }

    private sendRequest(method: string,
        params: any[]): Observable<PcrudResponse> {

        // this.log(`sendRequest(${method})`);

        return this.net.requestCompiled(
            new NetRequest(
                'open-ils.pcrud', method, params, this.session)
        );
    }

    private cud(action: string,
        list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        this.cudList = [].concat(list); // value or array

        this.log(`CUD(): ${action}`);

        this.cudIdx = 0;
        this.cudAction = action;
        this.xactCloseMode = 'commit';

        return this.wrapXact(() => {
            return new Observable(observer => {
                this.cudObserver = observer;
                this.nextCudRequest();
            });
        });
    }

    /**
     * Loops through the list of objects to update and sends
     * them one at a time to the server for processing.  Once
     * all are done, the cudObserver is resolved.
     */
    nextCudRequest(): void {
        if (this.cudIdx >= this.cudList.length) {
            this.cudObserver.complete();
            return;
        }

        let action = this.cudAction;
        const fmObj = this.cudList[this.cudIdx++];

        if (action === 'auto') {
            if (fmObj.ischanged()) { action = 'update'; }
            if (fmObj.isnew())     { action = 'create'; }
            if (fmObj.isdeleted()) { action = 'delete'; }

            if (action === 'auto') {
                // object does not need updating; move along
                return this.nextCudRequest();
            }
        }

        this.sendRequest(
            `open-ils.pcrud.${action}.${fmObj.classname}`,
            [this.token(), fmObj]
        ).subscribe({
            next: res => this.cudObserver.next(res),
            error: (err: unknown) => this.cudObserver.error(err),
            complete: ()  => this.nextCudRequest()
        });
    }
}

@Injectable({providedIn: 'root'})
export class PcrudService {
    static useAuthoritative = true;

    constructor(
        private idl: IdlService,
        private store: StoreService,
        private net: NetService,
        private auth: AuthService
    ) {}

    // Pass-thru functions for one-off PCRUD calls

    connect(): Promise<PcrudContext> {
        return this.newContext().connect();
    }

    newContext(): PcrudContext {
        return new PcrudContext(this.idl, this.net, this.auth);
    }

    retrieve(fmClass: string, pkey: Number | string,
        pcrudOps?: any, reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        return this.newContext().retrieve(fmClass, pkey, pcrudOps, reqOps);
    }

    retrieveAll(fmClass: string, pcrudOps?: any,
        reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        return this.newContext().retrieveAll(fmClass, pcrudOps, reqOps);
    }

    search(fmClass: string, search: any,
        pcrudOps?: any, reqOps?: PcrudReqOps): Observable<PcrudResponse> {
        return this.newContext().search(fmClass, search, pcrudOps, reqOps);
    }

    create(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.newContext().create(list);
    }

    update(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.newContext().update(list);
    }

    remove(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.newContext().remove(list);
    }

    autoApply(list: IdlObject | IdlObject[]): Observable<PcrudResponse> {
        return this.newContext().autoApply(list);
    }

    setAuthoritative(): void {
        const key = 'eg.sys.use_authoritative';

        // Track the value as clearable on login/logout.
        this.store.addLoginSessionKey(key);

        const enabled = this.store.getLoginSessionItem(key);

        if (typeof enabled === 'boolean') {
            PcrudService.useAuthoritative = enabled;
        } else {
            this.net.request(
                'open-ils.actor',
                'opensrf.open-ils.system.use_authoritative'
            ).subscribe({
                next: enabled => {
                    enabled = Boolean(Number(enabled));
                    PcrudService.useAuthoritative = enabled;
                    this.store.setLoginSessionItem(key, enabled);
                    console.debug('authoriative check function returned a value of ', enabled);
                    return enabled;
                },

                error: (err: unknown) => {
                    PcrudService.useAuthoritative = true;
                    this.store.setLoginSessionItem(key, true);
                    console.debug('authoriative check function failed somehow, assuming TRUE');
                },
                complete: () => console.debug('authoriative check function complete')
            });
        }
    }

    /* translateFlatSortSimple(sort: any[]): any {
        if (!sort || sort.length === 0) return null;

        return sort.reduce((acc, s) => {
            acc[s.name] = s.dir.toLowerCase();
            return acc;
        }, {});
    }*/

    translateFlatSortComplex(hint: string, sort: any[]): any {
        if (!sort || sort.length === 0) {return null;}

        return {
            order_by: sort.map(s => ({
                class: hint,
                field: s.name,
                direction: s.dir.toUpperCase()
            }))
        };
    }
}



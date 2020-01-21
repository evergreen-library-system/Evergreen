/**
 *
 * constructor(private net : NetService) {
 *   ...
 *   this.net.request(service, method, param1 [, param2, ...])
 *     .subscribe(
 *       (res) => console.log('received one resopnse: ' + res),
 *       (err) => console.error('recived request error: ' + err),
 *       ()    => console.log('request complete')
 *     )
 *   );
 *   ...
 *
 *  // Example translating a net request into a promise.
 *  this.net.request(service, method, param1)
 *  .toPromise().then(result => console.log(result));
 *
 * }
 *
 * Each response is relayed via Observable.next().  The interface is
 * the same for streaming and atomic requests.
 */
import {Injectable, EventEmitter} from '@angular/core';
import {Observable, Observer} from 'rxjs';
import {EventService, EgEvent} from './event.service';

// Global vars from opensrf.js
// These are availavble at runtime, but are not exported.
declare var OpenSRF, OSRF_TRANSPORT_TYPE_WS;

export class NetRequest {
    service: string;
    method: string;
    params: any[];
    observer: Observer<any>;
    superseded = false;
    // If set, this will be used instead of a one-off OpenSRF.ClientSession.
    session?: any;
    // True if we're using a single-use local session
    localSession = true;

    // Last Event encountered by this request.
    // Most callers will not need to import Event since the parsed
    // event will be available here.
    evt: EgEvent;

    constructor(service: string, method: string, params: any[], session?: any) {
        this.service = service;
        this.method = method;
        this.params = params;
        if (session) {
            this.session = session;
            this.localSession = false;
        } else {
            this.session = new OpenSRF.ClientSession(service);
        }
    }
}

export interface AuthExpiredEvent {
    // request is set when the auth expiration was determined as a
    // by-product of making an API call.
    request?: NetRequest;

    // True if this environment (e.g. browser tab) was notified of the
    // expired auth token from an external source (e.g. another browser tab).
    viaExternal?: boolean;
}

@Injectable({providedIn: 'root'})
export class NetService {

    permFailed$: EventEmitter<NetRequest>;
    authExpired$: EventEmitter<AuthExpiredEvent>;

    // If true, permission failures are emitted via permFailed
    // and the active request is marked as superseded.
    permFailedHasHandler: Boolean = false;

    constructor(
        private egEvt: EventService
    ) {
        this.permFailed$ = new EventEmitter<NetRequest>();
        this.authExpired$ = new EventEmitter<AuthExpiredEvent>();
    }

    // Standard request call -- Variadic params version
    request(service: string, method: string, ...params: any[]): Observable<any> {
        return this.requestWithParamList(service, method, params);
    }

    // Array params version
    requestWithParamList(service: string,
        method: string, params: any[]): Observable<any> {
        return this.requestCompiled(
            new NetRequest(service, method, params));
    }

    // Request with pre-compiled NetRequest
    requestCompiled(request: NetRequest): Observable<any> {
        return Observable.create(
            observer => {
                request.observer = observer;
                this.sendCompiledRequest(request);
            }
        );
    }

    // Send the compiled request to the server via WebSockets
    sendCompiledRequest(request: NetRequest): void {
        OpenSRF.Session.transport = OSRF_TRANSPORT_TYPE_WS;
        console.debug(`Net: request ${request.method}`);

        request.session.request({
            async  : true, // WS only operates in async mode
            method : request.method,
            params : request.params,
            oncomplete : () => {

                // TODO: teach opensrf.js to call cleanup() inside
                // disconnect() and teach Pcrud to call cleanup()
                // as needed to avoid long-lived session data bloat.
                if (request.localSession) {
                    request.session.cleanup();
                }

                // A superseded request will be complete()'ed by the
                // superseder at a later time.
                if (!request.superseded) {
                    request.observer.complete();
                }
            },
            onresponse : r => {
                this.dispatchResponse(request, r.recv().content());
            },
            onerror : errmsg => {
                const msg = `${request.method} failed! See server logs. ${errmsg}`;
                console.error(msg);
                request.observer.error(msg);
            },
            onmethoderror : (req, statCode, statMsg) => {
                const msg =
                    `${request.method} failed! stat=${statCode} msg=${statMsg}`;
                console.error(msg);

                if (request.service === 'open-ils.pcrud'
                    && Number(statCode) === 401) {
                    // 401 is the PCRUD equivalent of a NO_SESSION event
                    this.authExpired$.emit({request: request});
                }

                request.observer.error(msg);
            }

        }).send();
    }

    // Relay response object to the caller for typical/successful
    // responses.  Applies special handling to response events that
    // require global attention.
    private dispatchResponse(request, response): void {
        request.evt = this.egEvt.parse(response);

        if (request.evt) {
            switch (request.evt.textcode) {

                case 'NO_SESSION':
                    console.debug(`Net emitting event: ${request.evt}`);
                    request.observer.error(request.evt.toString());
                    this.authExpired$.emit({request: request});
                    return;

                case 'PERM_FAILURE':
                    if (this.permFailedHasHandler) {
                        console.debug(`Net emitting event: ${request.evt}`);
                        request.superseded = true;
                        this.permFailed$.emit(request);
                        return;
                    }
            }
        }

        // Pass the response to the caller.
        request.observer.next(response);
    }
}

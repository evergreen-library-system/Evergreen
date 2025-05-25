import {Injectable} from '@angular/core';
import {Observable, tap} from 'rxjs';
import {HttpClient} from '@angular/common/http';
import {saveAs} from 'file-saver';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {EventService} from '@eg/core/event.service';

export const VANDELAY_EXPORT_PATH = '/exporter';
export const VANDELAY_UPLOAD_PATH = '/vandelay-upload';

export class VandelayImportSelection {
    recordIds: number[];
    queue: IdlObject;
    importQueue: boolean; // import the whole queue
    overlayMap: {[qrId: number]: /* breId */ number};

    constructor() {
        this.recordIds = [];
        this.overlayMap = {};
    }
}

@Injectable()
export class VandelayService {

    allQueues: {[qtype: string]: IdlObject[]};
    attrDefs: {[atype: string]: IdlObject[]};
    bibSources: IdlObject[];
    bibBuckets: IdlObject[];
    copyStatuses: IdlObject[];
    matchSets: {[stype: string]: IdlObject[]};
    importItemAttrDefs: IdlObject[];
    bibTrashGroups: IdlObject[];
    mergeProfiles: IdlObject[];

    // Used for tracking records between the queue page and
    // the import page.  Fields managed externally.
    importSelection: VandelayImportSelection;

    // Track the last grid offset in the queue page so we
    // can return the user to the same page of data after
    // going to the matches page.
    queuePageOffset: number;

    constructor(
        private http: HttpClient,
        private idl: IdlService,
        private org: OrgService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private perm: PermService
    ) {
        this.attrDefs = {};
        this.allQueues = {};
        this.matchSets = {};
        this.importSelection = null;
        this.queuePageOffset = 0;
    }

    getAttrDefs(dtype: string): Promise<IdlObject[]> {
        if (this.attrDefs[dtype]) {
            return Promise.resolve(this.attrDefs[dtype]);
        }
        const cls = !dtype.match(/auth/) ? 'vqbrad' : 'vqarad';
        const orderBy = {};
        orderBy[cls] = 'id';
        return this.pcrud.retrieveAll(cls,
            {order_by: orderBy}, {atomic: true}).toPromise()
            .then(list => {
                this.attrDefs[dtype] = list;
                return list;
            });
    }

    getMergeProfiles(): Promise<IdlObject[]> {
        if (this.mergeProfiles) {
            return Promise.resolve(this.mergeProfiles);
        }

        const owners = this.org.ancestors(this.auth.user().ws_ou(), true);
        return this.pcrud.search('vmp',
            {owner: owners}, {order_by: {vmp: ['name']}}, {atomic: true})
            .toPromise().then(profiles => {
                this.mergeProfiles = profiles;
                return profiles;
            });
    }

    // Returns a promise resolved with the list of queues.
    getAllQueues(qtype: string): Promise<IdlObject[]> {
        if (this.allQueues[qtype]) {
            return Promise.resolve(this.allQueues[qtype]);
        } else {
            this.allQueues[qtype] = [];
        }

        const filter = {};
        let real_qtype = qtype;
        if (qtype === 'acq') {
            real_qtype = 'bib';
            filter['queue_type'] = qtype;
        }

        // could be a big list, invoke in streaming mode
        return this.net.request(
            'open-ils.vandelay',
            `open-ils.vandelay.${real_qtype}_queue.owner.retrieve`,
            this.auth.token(),null,filter
        ).pipe(tap(
            queue => this.allQueues[qtype].push(queue)
        )).toPromise().then(() => this.allQueues[qtype]);
    }

    getBibSources(): Promise<IdlObject[]> {
        if (this.bibSources) {
            return Promise.resolve(this.bibSources);
        }

        return this.pcrud.retrieveAll('cbs',
            {order_by: {cbs: 'id'}},
            {atomic: true}
        ).toPromise().then(sources => {
            this.bibSources = sources;
            return sources;
        });
    }

    getItemImportDefs(): Promise<IdlObject[]> {
        if (this.importItemAttrDefs) {
            return Promise.resolve(this.importItemAttrDefs);
        }

        const owners = this.org.ancestors(this.auth.user().ws_ou(), true);
        return this.pcrud.search('viiad', {owner: owners}, {}, {atomic: true})
            .toPromise().then(defs => {
                this.importItemAttrDefs = defs;
                return defs;
            });
    }

    // todo: differentiate between biblio and authority a la queue api
    getMatchSets(mtype: string): Promise<IdlObject[]> {

        const mstype = mtype.match(/bib/) ? 'biblio' : 'authority';

        if (this.matchSets[mtype]) {
            return Promise.resolve(this.matchSets[mtype]);
        } else {
            this.matchSets[mtype] = [];
        }

        const owners = this.org.ancestors(this.auth.user().ws_ou(), true);

        return this.pcrud.search('vms',
            {owner: owners, mtype: mstype}, {}, {atomic: true})
            .toPromise().then(sets => {
                this.matchSets[mtype] = sets;
                return sets;
            });
    }

    getBibBuckets(): Promise<IdlObject[]> {
        if (this.bibBuckets) {
            return Promise.resolve(this.bibBuckets);
        }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.retrieve_by_class',
            this.auth.token(), this.auth.user().id(), 'biblio', 'staff_client'
        ).toPromise().then(bkts => {
            this.bibBuckets = bkts;
            return bkts;
        });
    }

    getCopyStatuses(): Promise<any> {
        if (this.copyStatuses) {
            return Promise.resolve(this.copyStatuses);
        }
        return this.pcrud.retrieveAll('ccs', {}, {atomic: true})
            .toPromise().then(stats => {
                this.copyStatuses = stats;
                return stats;
            });
    }

    getBibTrashGroups(): Promise<any> {
        if (this.bibTrashGroups) {
            return Promise.resolve(this.bibTrashGroups);
        }

        const owners = this.org.ancestors(this.auth.user().ws_ou(), true);

        return this.pcrud.search('vibtg',
            {always_apply : 'f', owner: owners},
            {vibtg : ['label']},
            {atomic: true}
        ).toPromise().then(groups => {
            this.bibTrashGroups = groups;
            return groups;
        });
    }


    // Create a queue and return the ID of the new queue via promise.
    createQueue(
        queueName: string,
        recordType: string,
        importDefId: number,
        matchSet: number,
        matchBucket: number): Promise<number> {

        let real_recordType = recordType;
        if (recordType === 'acq') {
            real_recordType = 'bib';
        }

        const method = `open-ils.vandelay.${real_recordType}_queue.create`;

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.vandelay', method,
                this.auth.token(), queueName, null, recordType,
                matchSet, importDefId, matchBucket
            ).subscribe(queue => {
                const e = this.evt.parse(queue);
                if (e) {
                    reject(e);
                } else {
                    // createQueue is always called after queues have
                    // been fetched and cached.
                    this.allQueues[recordType].push(queue);
                    resolve(queue.id());
                }
            });
        });
    }

    getQueuedRecords(queueId: number, queueType: string,
        options?: any, limitToMatches?: boolean): Observable<any> {

        const qtype = queueType.match(/auth/) ? 'auth' : 'bib';

        let method =
          `open-ils.vandelay.${qtype}_queue.records.retrieve`;

        if (limitToMatches) {
            method =
              `open-ils.vandelay.${qtype}_queue.records.matches.retrieve`;
        }

        return this.net.request('open-ils.vandelay',
            method, this.auth.token(), queueId, options);
    }

    // Download a queue as a MARC file.
    exportQueue(queue: IdlObject, nonImported?: boolean) {

        const etype = queue.queue_type().match(/auth/) ? 'auth' : 'bib';

        let url =
          `${VANDELAY_EXPORT_PATH}?type=${etype}&queueid=${queue.id()}`;

        let saveName = queue.name();

        if (nonImported) {
            url += '&nonimported=1';
            saveName += '_nonimported';
        }

        saveName += '.mrc';

        this.http.get(url, {responseType: 'text'}).subscribe(
            { next: data => {
                saveAs(
                    new Blob([data], {type: 'application/octet-stream'}),
                    saveName
                );
            }, error: (err: unknown)  => {
                console.error(err);
            } }
        );
    }

    // Poll every 2 seconds for session tracker updates so long
    // as the session tracker is active.
    // Returns an Observable of tracker objects.
    pollSessionTracker(id: number): Observable<IdlObject> {
        return new Observable(observer => {
            this.getNextSessionTracker(id, observer);
        });
    }

    getNextSessionTracker(id: number, observer: any) {

        // No need for this to be an authoritative call.
        // It will complete eventually regardless.
        this.pcrud.retrieve('vst', id).subscribe(
            tracker => {
                if (tracker && tracker.state() === 'active') {
                    observer.next(tracker);
                    setTimeout(() =>
                        // eslint-disable-next-line no-magic-numbers
                        this.getNextSessionTracker(id, observer), 2000);
                } else {
                    console.debug(
                        `Vandelay session tracker ${id} is ${tracker.state()}`);
                    observer.complete();
                }
            }
        );
    }
}


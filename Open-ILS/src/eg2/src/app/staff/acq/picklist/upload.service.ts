import {Injectable} from '@angular/core';
import {Observable} from 'rxjs';
import {tap, map} from 'rxjs/operators';
import {HttpClient} from '@angular/common/http';
import {saveAs} from 'file-saver';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {EventService} from '@eg/core/event.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {VandelayImportSelection, VANDELAY_EXPORT_PATH} from '@eg/staff/cat/vandelay/vandelay.service'


@Injectable()
export class PicklistUploadService {

    allQueues: {[qtype: string]: IdlObject[]};
    attrDefs: {[atype: string]: IdlObject[]};
    bibSources: IdlObject[];
    matchSets: {[stype: string]: IdlObject[]};
    importItemAttrDefs: IdlObject[];
    mergeProfiles: IdlObject[];
    providersList: IdlObject[];
    fiscalYears: IdlObject[];
    selectionLists: IdlObject[];

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
        const cls = (dtype === 'bib') ? 'vqbrad' : 'vqarad';
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

    getProvidersList(): Promise<IdlObject[]> {
        if (this.providersList) {
            return Promise.resolve(this.providersList);
        }

        const owners = this.org.ancestors(this.auth.user().ws_ou(), true);
        return this.pcrud.search('acqpro',
            {owner: owners}, {order_by: {acqpro: ['code']}}, {atomic: true})
        .toPromise().then(providers => {
            this.providersList = providers;
            return providers;
        });
    }

    getSelectionLists(): Promise<IdlObject[]> {
        if (this.selectionLists) {
            return Promise.resolve(this.selectionLists);
        }

        const owners = this.auth.user().id();
        return this.pcrud.search('acqpl',
            {owner: owners}, {order_by: {acqpl: ['name']}}, {atomic: true})
        .toPromise().then(lists => {
            this.selectionLists = lists;
            return lists;
        });
    }
    // Returns a promise resolved with the list of queues.
    getAllQueues(qtype: string): Promise<IdlObject[]> {
        if (this.allQueues[qtype]) {
            return Promise.resolve(this.allQueues[qtype]);
        } else {
            this.allQueues[qtype] = [];
        }

        // could be a big list, invoke in streaming mode
        return this.net.request(
            'open-ils.vandelay',
            `open-ils.vandelay.${qtype}_queue.owner.retrieve`,
            this.auth.token()
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

    getFiscalYears(): Promise<IdlObject[]> {
        if (this.fiscalYears) {
            return Promise.resolve(this.fiscalYears);
        }

        return this.pcrud.retrieveAll('acqfy',
          {order_by: {acqfy: 'year'}},
          {atomic: true}
        ).toPromise().then(years => {
            this.fiscalYears = years;
            return years;
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






    // Create a queue and return the ID of the new queue via promise.
    createQueue(
        queueName: string,
        recordType: string,
        importDefId: number,
        matchSet: number): Promise<number> {

        const method = `open-ils.vandelay.${recordType}_queue.create`;

        let qType = recordType;
        if (recordType.match(/acq/)) {
            qType = 'bib';
        }

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.vandelay', method,
                this.auth.token(), queueName, null, qType,
                matchSet, importDefId
            ).subscribe(queue => {
                const e = this.evt.parse(queue);
                if (e) {
                    reject(e);
                } else {
                    // createQueue is always called after queues have
                    // been fetched and cached.
                    this.allQueues[qType].push(queue);
                    resolve(queue.id());
                }
            });
        });
    }

    getQueuedRecords(queueId: number, queueType: string,
      options?: any, limitToMatches?: boolean): Observable<any> {

        const qtype = queueType.match(/bib/) ? 'bib' : 'auth';

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
          `${VANDELAY_EXPORT_PATH}?type=bib&queueid=${queue.id()}`;

        let saveName = queue.name();

        if (nonImported) {
            url += '&nonimported=1';
            saveName += '_nonimported';
        }

        saveName += '.mrc';

        this.http.get(url, {responseType: 'text'}).subscribe(
            data => {
                saveAs(
                    new Blob([data], {type: 'application/octet-stream'}),
                    saveName
                );
            },
            err  => {
                console.error(err);
            }
        );
    }
}


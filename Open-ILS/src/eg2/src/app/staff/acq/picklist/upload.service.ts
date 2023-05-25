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
import {VandelayImportSelection} from '@eg/staff/cat/vandelay/vandelay.service';


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
    defaultFiscalYear: IdlObject;
    selectionLists: IdlObject[];
    queueType: string;
    recordType: string;


    importSelection: VandelayImportSelection;

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
        this.queueType = 'acq';
        this.recordType = 'bib';
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

    getAllQueues(qtype: string): Promise<IdlObject[]> {
        if (this.allQueues[qtype]) {
            return Promise.resolve(this.allQueues[qtype]);
        } else {
            this.allQueues[qtype] = [];
        }

        return this.net.request(
            'open-ils.vandelay',
            'open-ils.vandelay.bib_queue.owner.retrieve',
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

    getDefaultFiscalYear(org: number): Promise<IdlObject> {
        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.org_unit.current_fiscal_year',
            this.auth.token(), org
        ).pipe(tap(afy => {
            this.defaultFiscalYear = this.fiscalYears.filter(fy => Number(fy.year()) === Number(afy))[0];
        })).toPromise().then(() => {
            return this.defaultFiscalYear;
        });
    }

    getFiscalYears(org: number): Promise<IdlObject[]> {
        return this.pcrud.retrieveAll('acqfy',
            {order_by: {acqfy: 'year'}},
            {atomic: true}
        ).toPromise().then(years => {
            this.fiscalYears = years.filter( y => y.calendar() === this.org.get(org).fiscal_calendar());
            // if there are no entries, inject a special entry for the current year
            if (!this.fiscalYears.length) {
                const afy = this.idl.create('acqfy');
                afy.id(-1);
                afy.calendar(-1);
                const now = new Date();
                afy.year(now.getFullYear());
                this.fiscalYears = [ afy ];
            }
            return this.fiscalYears;
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

    getMatchSets(mtype: string): Promise<IdlObject[]> {

        const mstype = 'biblio';

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


    createQueue(
        queueName: string,
        queueType: string,
        importDefId: number,
        matchSet: number): Promise<number> {

        const method = 'open-ils.vandelay.bib_queue.create';
        queueType = 'acq';


        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.vandelay', method,
                this.auth.token(), queueName, null, queueType,
                matchSet, importDefId
            ).subscribe(queue => {
                const e = this.evt.parse(queue);
                if (e) {
                    reject(e);
                } else {
                    this.allQueues['bib'].push(queue);
                    resolve(queue.id());
                }
            });
        });
    }

    createSelectionList(
        picklistName: string,
        picklistOrg: number
    ): Promise<number> {

        const newpicklist = this.idl.create('acqpl');
        newpicklist.owner(this.auth.user().id());
        newpicklist.name(picklistName);
        newpicklist.org_unit(picklistOrg);

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.acq', 'open-ils.acq.picklist.create',
                this.auth.token(), newpicklist
            ).subscribe((picklist) => {
                if (this.evt.parse(picklist)) {
                    console.error(picklist);
                } else {
                    console.debug(picklist);
                    resolve(picklist);
                }
            });
        });
    }

}


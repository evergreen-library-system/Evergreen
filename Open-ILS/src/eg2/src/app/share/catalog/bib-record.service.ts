import {Injectable} from '@angular/core';
import {Observable, from} from 'rxjs';
import {mergeMap, map, tap} from 'rxjs/operators';
import {OrgService} from '@eg/core/org.service';
import {UnapiService} from '@eg/share/catalog/unapi.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';

export const NAMESPACE_MAPS = {
    'mods':     'http://www.loc.gov/mods/v3',
    'biblio':   'http://open-ils.org/spec/biblio/v1',
    'holdings': 'http://open-ils.org/spec/holdings/v1',
    'indexing': 'http://open-ils.org/spec/indexing/v1'
};

export const HOLDINGS_XPATH =
    '/holdings:holdings/holdings:counts/holdings:count';


export class BibRecordSummary {
    id: number; // == record.id() for convenience
    metabibId: number; // If present, this is a metabib summary
    metabibRecords: number[]; // all constituent bib records
    orgId: number;
    orgDepth: number;
    record: IdlObject;
    display: any;
    attributes: any;
    holdingsSummary: any;
    holdCount: number;
    bibCallNumber: string;
    net: NetService;
    displayHighlights: {[name: string]: string | string[]} = {};

    constructor(record: IdlObject, orgId: number, orgDepth?: number) {
        this.id = Number(record.id());
        this.record = record;
        this.orgId = orgId;
        this.orgDepth = orgDepth;
        this.display = {};
        this.attributes = {};
        this.bibCallNumber = null;
        this.metabibRecords = [];
    }

    // Get -> Set -> Return bib-level call number
    getBibCallNumber(): Promise<string> {

        if (this.bibCallNumber !== null) {
            return Promise.resolve(this.bibCallNumber);
        }

        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.marc_cn.retrieve',
            this.id, null, this.orgId
        ).toPromise().then(cnArray => {
            if (cnArray && cnArray.length > 0) {
                const key1 = Object.keys(cnArray[0])[0];
                this.bibCallNumber = cnArray[0][key1];
            } else {
                this.bibCallNumber = '';
            }
            return this.bibCallNumber;
        });
    }
}

@Injectable()
export class BibRecordService {

    // Cache of bib editor / creator objects
    // Assumption is this list will be limited in size.
    userCache: {[id: number]: IdlObject};

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private unapi: UnapiService,
        private pcrud: PcrudService
    ) {
        this.userCache = {};
    }

    getBibSummary(id: number,
        orgId?: number, isStaff?: boolean): Observable<BibRecordSummary> {
        return this.getBibSummaries([id], orgId, isStaff);
    }

    getBibSummaries(bibIds: number[],
        orgId?: number, isStaff?: boolean): Observable<BibRecordSummary> {

        if (bibIds.length === 0) { return from([]); }
        if (!orgId) { orgId = this.org.root().id(); }

        let method = 'open-ils.search.biblio.record.catalog_summary';
        if (isStaff) { method += '.staff'; }

        return this.net.request('open-ils.search', method, orgId, bibIds)
        .pipe(map(bibSummary => {
            const summary = new BibRecordSummary(bibSummary.record, orgId);
            summary.net = this.net; // inject
            summary.display = bibSummary.display;
            summary.attributes = bibSummary.attributes;
            summary.holdCount = bibSummary.hold_count;
            summary.holdingsSummary = bibSummary.copy_counts;
            return summary;
        }));
    }

    getMetabibSummaries(metabibIds: number[],
        orgId?: number, isStaff?: boolean): Observable<BibRecordSummary> {

        if (metabibIds.length === 0) { return from([]); }
        if (!orgId) { orgId = this.org.root().id(); }

        let method = 'open-ils.search.biblio.metabib.catalog_summary';
        if (isStaff) { method += '.staff'; }

        return this.net.request('open-ils.search', method, orgId, metabibIds)
        .pipe(map(metabibSummary => {
            const summary = new BibRecordSummary(metabibSummary.record, orgId);
            summary.net = this.net; // inject
            summary.metabibId = Number(metabibSummary.metabib_id);
            summary.metabibRecords = metabibSummary.metabib_records;
            summary.display = metabibSummary.display;
            summary.attributes = metabibSummary.attributes;
            summary.holdCount = metabibSummary.hold_count;
            summary.holdingsSummary = metabibSummary.copy_counts;
            return summary;
        }));
    }
}



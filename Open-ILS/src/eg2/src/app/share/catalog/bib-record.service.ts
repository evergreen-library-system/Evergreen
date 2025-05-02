import {Injectable} from '@angular/core';
import {Observable, from} from 'rxjs';
import {map} from 'rxjs/operators';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PermService} from '@eg/core/perm.service';

export const NAMESPACE_MAPS = {
    'mods':     'http://www.loc.gov/mods/v3',
    'biblio':   'http://open-ils.org/spec/biblio/v1',
    'holdings': 'http://open-ils.org/spec/holdings/v1',
    'indexing': 'http://open-ils.org/spec/indexing/v1'
};

export const HOLDINGS_XPATH =
    '/holdings:holdings/holdings:counts/holdings:count';

interface EResourceUrl {
    href: string;
    note: string;
    label: string;
}

export interface HoldingsSummary {
    org_unit: number;
    depth: number;
    unshadow: number;
    count: number;
    available: number;
    transcendant: number;
}

export class BibRecordSummary {
    id: number; // == record.id() for convenience
    metabibId: number; // If present, this is a metabib summary
    metabibRecords: number[]; // all constituent bib records
    staffViewMetabibId: number; // to supplement a record summary
    staffViewMetabibRecords: number[]; // to supplement a record summary
    staffViewMetabibAttributes: any; // to supplement a record summary
    orgId: number;
    orgDepth: number;
    record: IdlObject;
    display: any;
    attributes: any;
    holdingsSummary: HoldingsSummary[];
    prefOuHoldingsSummary: HoldingsSummary[];
    holdCount: number;
    recordNoteCount: number;
    bibCallNumber: string;
    firstCallNumber: string;
    net: NetService;
    displayHighlights: {[name: string]: string | string[]} = {};
    eResourceUrls: EResourceUrl[] = [];
    copies: any[];
    isHoldable: boolean;

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
    allowUnfillableHolds: boolean;

    constructor(
        private net: NetService,
        private org: OrgService,
        private perm: PermService
    ) {
        this.userCache = {};
        this.perm.hasWorkPermHere(['PLACE_UNFILLABLE_HOLD'])
            .then(perms => {
                this.allowUnfillableHolds = perms.PLACE_UNFILLABLE_HOLD;
            });
    }

    getBibSummary(id: number,
        orgId?: number, isStaff?: boolean,
        library_group?: number): Observable<BibRecordSummary> {
        const opts = library_group ? {library_group: library_group} : {};
        return this.getBibSummaries([id], orgId, isStaff, opts);
    }

    getBibSummaries(bibIds: number[], orgId?: number,
        isStaff?: boolean, options?: any): Observable<BibRecordSummary> {

        if (bibIds.length === 0) { return from([]); }
        if (!orgId) { orgId = this.org.root().id(); }

        let method = 'open-ils.search.biblio.record.catalog_summary';
        if (isStaff) { method += '.staff'; }

        return this.net.request('open-ils.search', method, orgId, bibIds, options)
            .pipe(map(bibSummary => {
                const summary = new BibRecordSummary(bibSummary.record, orgId);
                summary.net = this.net; // inject
                summary.staffViewMetabibId = Number(bibSummary.staff_view_metabib_id);
                summary.staffViewMetabibRecords = bibSummary.staff_view_metabib_records;
                summary.staffViewMetabibAttributes = bibSummary.staff_view_metabib_attributes;
                summary.display = bibSummary.display;
                summary.attributes = bibSummary.attributes;
                summary.holdCount = Number(bibSummary.hold_count);
                summary.recordNoteCount = Number(bibSummary.record_note_count);
                summary.holdingsSummary = bibSummary.copy_counts;
                summary.copies = bibSummary.copies;
                summary.firstCallNumber = bibSummary.first_call_number;
                summary.prefOuHoldingsSummary = bibSummary.pref_ou_copy_counts;

                summary.isHoldable = bibSummary.record.deleted() === 'f'
                && bibSummary.has_holdable_copy
                || this.allowUnfillableHolds;

                // De-duplicate urls, frequently caused by multiple subfield 9's
                // Note that .forEach() and .every() pass their callback functions the
                // parameters (element, index, array) such that element = array[index]
                // and they need to be distinctly named when sharing scope.
                bibSummary.urls.forEach(function (elb, indb, aryb) {
                    if(summary.eResourceUrls.every((els, inds, arys) =>
                        elb.href !== els.href || elb.note !== els.note || elb.label !== els.label)) {
                        summary.eResourceUrls.push(elb);
                    }
                });

                return summary;
            }));
    }

    getMetabibSummaries(metabibIds: number[],
        orgId?: number, isStaff?: boolean, options?: any): Observable<BibRecordSummary> {

        if (metabibIds.length === 0) { return from([]); }
        if (!orgId) { orgId = this.org.root().id(); }

        let method = 'open-ils.search.biblio.metabib.catalog_summary';
        if (isStaff) { method += '.staff'; }

        return this.net.request('open-ils.search', method, orgId, metabibIds, options)
            .pipe(map(metabibSummary => {
                const summary = new BibRecordSummary(metabibSummary.record, orgId);
                summary.net = this.net; // inject
                summary.metabibId = Number(metabibSummary.metabib_id);
                summary.metabibRecords = metabibSummary.metabib_records;
                summary.display = metabibSummary.display;
                summary.attributes = metabibSummary.attributes;
                summary.holdCount = metabibSummary.hold_count;
                summary.holdingsSummary = metabibSummary.copy_counts;
                summary.copies = metabibSummary.copies;
                summary.firstCallNumber = metabibSummary.first_call_number;
                summary.prefOuHoldingsSummary = metabibSummary.pref_ou_copy_counts;

                summary.isHoldable = metabibSummary.record.deleted() === 'f'
                && metabibSummary.has_holdable_copy
                || this.allowUnfillableHolds;

                return summary;
            }));
    }
}



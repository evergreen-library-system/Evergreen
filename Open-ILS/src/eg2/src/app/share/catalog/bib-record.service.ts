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

    constructor(record: IdlObject, orgId: number, orgDepth: number) {
        this.id = Number(record.id());
        this.record = record;
        this.orgId = orgId;
        this.orgDepth = orgDepth;
        this.display = {};
        this.attributes = {};
        this.bibCallNumber = null;
        this.metabibRecords = [];
    }

    ingest() {
        this.compileDisplayFields();
        this.compileRecordAttrs();

        // Normalize some data for JS consistency
        this.record.creator(Number(this.record.creator()));
        this.record.editor(Number(this.record.editor()));
    }

    compileDisplayFields() {
        this.record.flat_display_entries().forEach(entry => {
            if (entry.multi() === 't') {
                if (this.display[entry.name()]) {
                    this.display[entry.name()].push(entry.value());
                } else {
                    this.display[entry.name()] = [entry.value()];
                }
            } else {
                this.display[entry.name()] = entry.value();
            }
        });
    }

    compileRecordAttrs() {
        // Any attr can be multi-valued.
        this.record.mattrs().forEach(attr => {
            if (this.attributes[attr.attr()]) {
                // Avoid dupes
                if (this.attributes[attr.attr()].indexOf(attr.value()) < 0) {
                    this.attributes[attr.attr()].push(attr.value());
                }
            } else {
                this.attributes[attr.attr()] = [attr.value()];
            }
        });
    }

    // Get -> Set -> Return bib hold count
    getHoldCount(): Promise<number> {

        if (Number.isInteger(this.holdCount)) {
            return Promise.resolve(this.holdCount);
        }

        let method = 'open-ils.circ.bre.holds.count';
        let target = this.id;

        if (this.metabibId) {
            method = 'open-ils.circ.mmr.holds.count';
            target = this.metabibId;
        }

        return this.net.request(
            'open-ils.circ', method, target
        ).toPromise().then(count => this.holdCount = count);
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

    // Avoid fetching the MARC blob by specifying which fields on the
    // bre to select.  Note that fleshed fields are implicitly selected.
    fetchableBreFields(): string[] {
        return this.idl.classes.bre.fields
            .filter(f => !f.virtual && f.name !== 'marc')
            .map(f => f.name);
    }

    // Note when multiple IDs are provided, responses are emitted in order
    // of receipt, not necessarily in the requested ID order.
    getBibSummary(bibIds: number | number[],
        orgId?: number, orgDepth?: number): Observable<BibRecordSummary> {

        const ids = [].concat(bibIds);

        if (ids.length === 0) {
            return from([]);
        }

        return this.pcrud.search('bre', {id: ids},
            {   flesh: 1,
                flesh_fields: {bre: ['flat_display_entries', 'mattrs']},
                select: {bre : this.fetchableBreFields()}
            },
            {anonymous: true} // skip unneccesary auth
        ).pipe(mergeMap(bib => {
            const summary = new BibRecordSummary(bib, orgId, orgDepth);
            summary.net = this.net; // inject
            summary.ingest();
            return this.getHoldingsSummary(bib.id(), orgId, orgDepth)
            .then(holdingsSummary => {
                summary.holdingsSummary = holdingsSummary;
                return summary;
            });
        }));
    }

    // A Metabib Summary is a BibRecordSummary with the lead record as
    // its core bib record plus attributes (e.g. formats) from related
    // records.
    getMetabibSummary(metabibIds: number | number[],
        orgId?: number, orgDepth?: number): Observable<BibRecordSummary> {

        const ids = [].concat(metabibIds);

        if (ids.length === 0) {
            return from([]);
        }

        return this.pcrud.search('mmr', {id: ids},
            {flesh: 1, flesh_fields: {mmr: ['source_maps']}},
            {anonymous: true}
        ).pipe(mergeMap(mmr => this.compileMetabib(mmr, orgId, orgDepth)));
    }

    // 'metabib' must have its "source_maps" field fleshed.
    // Get bib summaries for all related bib records so we can
    // extract data that must be appended to the master record summary.
    compileMetabib(metabib: IdlObject,
        orgId?: number, orgDepth?: number): Observable<BibRecordSummary> {

        // TODO: Create an API similar to the one that builds a combined
        // mods blob for metarecords, except using display fields, etc.
        // For now, this seems to get the job done.

        // Non-master records
        const relatedBibIds = metabib.source_maps()
            .map(m => m.source())
            .filter(id => id !== metabib.master_record());

        let observer;
        const observable = new Observable<BibRecordSummary>(o => observer = o);

        // NOTE: getBibSummary calls getHoldingsSummary against
        // the bib record unnecessarily.  It's called again below.
        // Reconsider this approach (see also note above about API).
        this.getBibSummary(metabib.master_record(), orgId, orgDepth)
        .subscribe(summary => {
            summary.metabibId = Number(metabib.id());
            summary.metabibRecords =
                metabib.source_maps().map(m => Number(m.source()));

            let promise;

            if (relatedBibIds.length > 0) {

                // Grab data for MR bib summary augmentation
                promise = this.pcrud.search('mraf', {id: relatedBibIds})
                    .pipe(tap(attr => summary.record.mattrs().push(attr)))
                    .toPromise();
            } else {

                // Metarecord has only one constituent bib.
                promise = Promise.resolve();
            }

            promise.then(() => {

                // Re-compile with augmented data
                summary.compileRecordAttrs();

                // Fetch holdings data for the metarecord
                this.getHoldingsSummary(metabib.id(), orgId, orgDepth, true)
                .then(holdingsSummary => {
                    summary.holdingsSummary = holdingsSummary;
                    observer.next(summary);
                    observer.complete();
                });
            });
        });

        return observable;
    }

    // Flesh the creator and editor fields.
    // Handling this separately lets us pull from the cache and
    // avoids the requirement that the main bib query use a staff
    // (VIEW_USER) auth token.
    fleshBibUsers(records: IdlObject[]): Promise<void> {

        const search = [];

        records.forEach(rec => {
            ['creator', 'editor'].forEach(field => {
                const id = rec[field]();
                if (Number.isInteger(id)) {
                    if (this.userCache[id]) {
                        rec[field](this.userCache[id]);
                    } else if (!search.includes(id)) {
                        search.push(id);
                    }
                }
            });
        });

        if (search.length === 0) {
            return Promise.resolve();
        }

        return this.pcrud.search('au', {id: search})
        .pipe(map(user => {
            this.userCache[user.id()] = user;
            records.forEach(rec => {
                if (user.id() === rec.creator()) {
                    rec.creator(user);
                }
                if (user.id() === rec.editor()) {
                    rec.editor(user);
                }
            });
        })).toPromise();
    }

    getHoldingsSummary(recordId: number,
        orgId: number, orgDepth: number, isMetarecord?: boolean): Promise<any> {

        const holdingsSummary = [];

        return this.unapi.getAsXmlDocument({
            target: isMetarecord ? 'mmr' : 'bre',
            id: recordId,
            extras: '{holdings_xml}',
            format: 'holdings_xml',
            orgId: orgId,
            depth: orgDepth
        }).then(xmlDoc => {

            // namespace resolver
            const resolver: any = (prefix: string): string => {
                return NAMESPACE_MAPS[prefix] || null;
            };

            // Extract the holdings data from the unapi xml doc
            const result = xmlDoc.evaluate(HOLDINGS_XPATH,
                xmlDoc, resolver, XPathResult.ANY_TYPE, null);

            let node;
            while (node = result.iterateNext()) {
                const counts = {type : node.getAttribute('type')};
                ['depth', 'org_unit', 'transcendant',
                    'available', 'count', 'unshadow'].forEach(field => {
                    counts[field] = Number(node.getAttribute(field));
                });
                holdingsSummary.push(counts);
            }

            return holdingsSummary;
        });
    }
}



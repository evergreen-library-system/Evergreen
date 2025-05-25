import {Component, OnInit, Renderer2} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {HttpClient} from '@angular/common/http';
import {tap} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {MarcRecord} from '@eg/staff/share/marc-edit/marcrecord';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {ServerStoreService} from '@eg/core/server-store.service';

const SESSION_POLL_INTERVAL = 2; // seconds
const MERGE_TEMPLATE_PATH = '/opac/extras/merge_template';

interface TemplateRule {
    ruleType: 'r' | 'a' | 'd';
    marcTag?: string;
    marcSubfields?: string;
    marcData?: string;
    advSubfield?: string;
    advRegex?: string;
}

@Component({
    templateUrl: 'marcbatch.component.html'
})
export class MarcBatchComponent implements OnInit {

    session: string;
    source: 'b' | 'c' | 'r' = 'b';
    buckets: ComboboxEntry[];
    bucket: number;
    recordId: number;
    csvColumn = 0;
    csvFile: File;
    templateRules: TemplateRule[] = [];
    record: MarcRecord;

    processing = false;
    progressMax: number = null;
    progressValue: number = null;
    numSucceeded = 0;
    numFailed = 0;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private http: HttpClient,
        private renderer: Renderer2,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        private cache: AnonCacheService
    ) {}

    ngOnInit() {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.bucket = +params.get('bucketId');
            this.recordId = +params.get('recordId');

            if (this.bucket) {
                this.source = 'b';
            } else if (this.recordId) {
                this.source = 'r';
            }
        });

        this.load();
    }

    load() {
        this.addRule();
        this.getBuckets();
    }

    rulesetToRecord(resetRuleData?: boolean) {
        this.record = new MarcRecord();

        this.templateRules.forEach(rule => {

            if (!rule.marcTag) { return; }

            let ruleText = rule.marcTag + (rule.marcSubfields || '');
            if (rule.advSubfield) {
                ruleText +=
                    `[${rule.advSubfield || ''} ~ ${rule.advRegex || ''}]`;
            }

            // Merge behavior is encoded in the 905 field.
            const ruleTag = this.record.newField({
                tag: '905',
                ind1: ' ',
                ind2: ' ',
                subfields: [[rule.ruleType, ruleText, 0]]
            });

            this.record.insertOrderedFields(ruleTag);

            if (rule.ruleType === 'd') {
                rule.marcData = '';
                return;
            }

            const dataRec = new MarcRecord();
            if (resetRuleData || !rule.marcData) {

                // Build a new value for the 'MARC Data' field based on
                // changes to the selected tag or subfields.

                const subfields = rule.marcSubfields ?
                    rule.marcSubfields.split('').map((sf, idx) => [sf, '', idx])
                    : [];

                dataRec.appendFields(
                    dataRec.newField({
                        tag: rule.marcTag,
                        ind1: ' ',
                        ind2: ' ',
                        subfields: subfields
                    })
                );

                console.log(dataRec.toBreaker());
                rule.marcData = dataRec.toBreaker().split(/\n/)[1];

            } else {

                // Absorb the breaker data already in the 'MARC Data' field
                // so it can be added to the template record in progress.

                dataRec.breakerText = rule.marcData;
                dataRec.absorbBreakerChanges();
            }

            this.record.appendFields(dataRec.fields[0]);
        });
    }

    breakerRows(): number {
        if (this.record) {
            const breaker = this.record.toBreaker();
            if (breaker) {
                return breaker.split(/\n/).length + 1;
            }
        }
        // eslint-disable-next-line no-magic-numbers
        return 3;
    }

    breaker(): string {
        return this.record ? this.record.toBreaker() : '';
    }

    addRule() {
        this.templateRules.push({ruleType: 'r'});
    }

    removeRule(idx: number) {
        this.templateRules.splice(idx, 1);
    }

    getBuckets(): Promise<any> {
        if (this.buckets) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.retrieve_by_class',
            this.auth.token(), this.auth.user().id(),
            'biblio', ['staff_client', 'vandelay_queue']

        ).pipe(tap(buckets => {
            this.buckets = buckets
                .sort((b1, b2) => b1.name() < b2.name() ? -1 : 1)
                .map(b => ({id: b.id(), label: b.name()}));

        })).toPromise();
    }

    bucketChanged(entry: ComboboxEntry) {
        this.bucket = entry ? entry.id : null;
    }

    fileSelected($event) {
        this.csvFile = $event.target.files[0];
    }

    disableSave(): boolean {
        if (!this.record || !this.source || this.processing) {
            return true;
        }

        if (this.source === 'b') {
            return !this.bucket;

        } else if (this.source === 'c') {
            return (this.csvColumn < 0 || !this.csvFile);

        } else if (this.source === 'r') {
            return !this.recordId;
        }
    }

    process() {
        this.processing = true;
        this.progressValue = null;
        this.progressMax = null;
        this.numSucceeded = 0;
        this.numFailed = 0;
        this.setReplaceMode();
        this.postForm().then(_ => this.pollProgress());
    }

    setReplaceMode() {
        if (this.record.subfield('905', 'r').length === 0) {
            // Force replace mode w/ no-op replace rule.
            this.record.appendFields(
                this.record.newField({
                    tag : '905',
                    ind1 : ' ',
                    ind2 : ' ',
                    subfields : [['r', '901c']]
                })
            );
        }
    }

    postForm(): Promise<any> {

        const formData: FormData = new FormData();
        formData.append('ses', this.auth.token());
        formData.append('skipui', '1');
        formData.append('template', this.record.toXml());
        formData.append('recordSource', this.source);
        formData.append('xactPerRecord', '1');

        if (this.source === 'b') {
            formData.append('containerid', this.bucket + '');

        } else if (this.source === 'c') {
            formData.append('idcolumn', this.csvColumn + '');
            formData.append('idfile', this.csvFile, this.csvFile.name);

        } else if (this.source === 'r') {
            formData.append('recid', this.recordId + '');
        }

        return this.http.post(
            MERGE_TEMPLATE_PATH, formData, {responseType: 'text'})
            .pipe(tap(cacheKey => this.session = cacheKey))
            .toPromise();
    }

    pollProgress(): Promise<any> {
        console.debug('Polling session ', this.session);

        return this.cache.getItem(this.session, 'batch_edit_progress')
            .then(progress => {
            // {"success":"t","complete":1,"failed":0,"succeeded":252}

                if (!progress) {
                    console.error('No batch edit session found for ', this.session);
                    return;
                }

                this.progressValue = progress.succeeded;
                this.progressMax = progress.total;
                this.numSucceeded = progress.succeeded;
                this.numFailed = progress.failed;

                if (progress.complete) {
                    this.processing = false;
                    return;
                }

                setTimeout(() => this.pollProgress(), SESSION_POLL_INTERVAL * 1000);
            });
    }
}


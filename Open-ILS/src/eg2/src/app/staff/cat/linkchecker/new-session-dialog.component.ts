import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {AuthService} from '@eg/core/auth.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {Component, Input, OnInit, ViewChild, Renderer2, OnDestroy} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {EventService} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {NgForm} from '@angular/forms';
import {PcrudService} from '@eg/core/pcrud.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {Subject, Subscription, Observable, debounceTime, distinctUntilChanged} from 'rxjs';

@Component({
    selector: 'eg-new-session-dialog',
    templateUrl: './new-session-dialog.component.html'
})

export class NewSessionDialogComponent extends DialogComponent implements OnInit, OnDestroy {

    @Input() sessionToClone: any; // not really a "session", but a combined session/batch view

    progressText = '';

    savedSearchIdlClass = 'asq';

    encounteredError = false;
    nameCollision = false;

    subscriptions: Subscription[] = [];

    sessionId: number;
    sessionName = '';
    sessionNameModelChanged: Subject<string> = new Subject<string>();

    sessionOwningLibrary: IdlObject;
    sessionSearchScope: IdlObject;
    sessionSearch = '';
    sessionSavedSearch: number = null;

    selectorModels: any = {
        'tag' : [],
        'subfields' : []
    };
    savedSearchEntries: ComboboxEntry[] = [];
    savedSearchObjectCache: any = {};

    @ViewChild('newSessionForm', { static: false}) newSessionForm: NgForm;
    @ViewChild('savedSearchSelector', { static: true}) savedSearchSelector: ComboboxComponent;
    @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;
    @ViewChild('progress', { static: true }) private progress: ProgressDialogComponent;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private evt: EventService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private renderer: Renderer2,
    ) {
        super(modal);
        if (this.modal) { /* empty */ } // noop for linting
    }

    ngOnInit() {

        this.subscriptions.push( this.onOpen$.subscribe(
            _ => {
                this.stopProgressMeter();
                if (this.sessionToClone) {
                    console.log('this.sessionToClone', this.sessionToClone);
                    this.sessionName = 'Copy of ' + this.sessionToClone.name;
                    this.sessionOwningLibrary = this.sessionToClone.owning_lib;
                    this.sessionSearch = this.sessionToClone.search;
                    // eslint-disable-next-line rxjs-x/no-nested-subscribe
                    this.pcrud.search('uvus', {'session':this.sessionToClone.session_id},{},{'atomic':true}).subscribe(
                        (list) => {
                            console.log('list',list);
                            list.forEach( (s: any,idx: number) => {
                                const xpath = s.xpath();
                                this.selectorModels.tag[idx] = xpath.match(/tag='(\d+)'/)[1];
                                this.selectorModels.subfields[idx] = '';
                                const matches = xpath.matchAll(/code='(.)'/g);
                                for (const match of matches) {
                                    this.selectorModels.subfields[idx] += match[1];
                                }
                                console.log('idx',idx);
                                console.log('xpath',xpath);
                                console.log('tag',this.selectorModels.tag[idx]);
                                console.log('subfields',this.selectorModels.subfields[idx]);
                            });
                        }
                    );
                }
                const el = this.renderer.selectRootElement('#session_name');
                if (el) { el.focus(); el.select(); }
            }
        ));

        this.sessionOwningLibrary = this.auth.user().ws_ou();
        this.selectorModels['tag'][0] = '856';
        this.selectorModels['subfields'][0] = 'u';

        this.subscriptions.push(
            this.pcrud.retrieveAll(this.savedSearchIdlClass).subscribe(search => {
                this.savedSearchEntries.push({id: search.id(), label: search.label()});
                this.savedSearchObjectCache[ search.id() ] = search;
            }
            ));

        this.subscriptions.push(
            this.sessionNameModelChanged
                .pipe(
                    // eslint-disable-next-line no-magic-numbers
                    debounceTime(300),
                    distinctUntilChanged()
                )
                .subscribe( newText => {
                    this.sessionName = newText;
                    this.nameCollision = false;
                    this.subscriptions.push(
                        this.pcrud.search('uvs',{
                            owning_lib: this.sessionOwningLibrary,
                            name: this.sessionName},{})
                            // eslint-disable-next-line rxjs-x/no-nested-subscribe
                            .subscribe( () => { this.nameCollision = true; })
                    );
                })
        );
        console.log('new-session-dialog this', this);
    }

    ngOnDestroy() {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

    applyOwningLibrary(p: any) {
        // [applyOrgId]="sessionOwningLibrary" is working fine
        if (p) { /* empty */ } // noop for linting
    }

    applySessionSearch(p: any) {
        if (p) { /* empty */ } // noop for linting
    }

    applySearchScope(p: any) {
        // [applyOrgId]="sessionSearchScope" was not working fine.
        // This also preserves null's, which is important since we'll
        // reapply this scope if applicable after applying a saved
        // search.
        this.sessionSearchScope = p;
        if (p) {
            this.sessionSearch = this.sessionSearch.replace(
                /^(.*)(site\(.+?\))(.*)$/,
                '$1site(' + p.shortname() + ')$3'
            );
            if (! this.sessionSearch.match(/site\(.+?\)/)) {
                this.sessionSearch += ' site(' + p.shortname() + ')';
            }
        }
    }

    applySavedSearch(p: any) {
        const obj = this.savedSearchObjectCache[p.id];
        if (obj) {
            this.sessionSearch = obj.query_text();
            this.applySearchScope( this.sessionSearchScope );
        }
    }

    // https://stackoverflow.com/questions/42322968/angular2-dynamic-input-field-lose-focus-when-input-changes
    trackByIdx(index: any, item: any) {
        if (item) { /* empty */ } // noop for linting
        return index;
    }

    addSelectorRow(index: number): void {
        this.selectorModels['tag'].splice(index, 0, '');
        this.selectorModels['subfields'].splice(index, 0, '');
    }

    delSelectorRow(index: number): void {
        this.selectorModels['tag'].splice(index, 1);
        this.selectorModels['subfields'].splice(index, 1);
    }

    stopProgressMeter() {
        this.progress.close();
        this.progress.reset();
    }

    resetProgressMeter(s: string) {
        this.progressText = s;
        this.progress.reset();
    }

    startProgressMeter(s: string) {
        this.progressText = s;
        this.progress.reset();
        this.progress.open();
    }

    createNewSession(options: any) {
        // /////////////////////////////////////////////
        options['verified_total_processed'] = 0;
        options['url_selectors_created'] = 0;
        options['urls_extracted'] = 0;
        this.startProgressMeter($localize`Creating session...`);
        this.subscriptions.push(this.net.request(
            'open-ils.url_verify',
            'open-ils.url_verify.session.create',
            this.auth.token(),
            this.sessionName,
            this.sessionSearch,
            this.sessionOwningLibrary
        ).subscribe({
            next: (res) => {
                if (this.evt.parse(res)) {
                    console.error('session.create ils_event',res);
                    this.fail.open();
                    this.stopProgressMeter();
                    this.close(false);
                } else {
                    this.sessionId = res;
                    options['sessionId'] = res;
                    // ///////////////////////////////////////////////////
                    this.resetProgressMeter($localize`Creating URL selectors...`);
                    this.subscriptions.push(
                        // eslint-disable-next-line rxjs-x/no-nested-subscribe
                        this.createUrlSelectors().subscribe({
                            next: (res2) => {
                                if (this.evt.parse(res2)) {
                                    console.error('url_selector.create error',res2);
                                    this.fail.open();
                                    this.stopProgressMeter();
                                    this.close(false);
                                } else {
                                    // console.log('url_selector',res2);
                                    options['url_selectors_created'] += 1;
                                }
                            },
                            error: (err2: unknown) => {
                                console.error('url_selector.create error',err2);
                                this.fail.open();
                                this.stopProgressMeter();
                                this.close(false);
                            },
                            complete: () => {
                                // //////////////////////////////////////////////////////////
                                this.resetProgressMeter($localize`Searching and extracting URLs...`);
                                this.subscriptions.push(this.net.request(
                                    'open-ils.url_verify',
                                    'open-ils.url_verify.session.search_and_extract',
                                    this.auth.token(),
                                    this.sessionId
                                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                                ).subscribe({
                                    next: (res3) => {
                                        console.log('res3',res3);
                                        if (!this.progress.hasMax()) {
                                            // first response returned by the API is the number of search results
                                            options['number_of_hits'] = Number(res3);
                                            // We'll become a determinate progress meter for this section
                                            this.progress.update({max: res3, value: 0});
                                        } else {
                                            // subsequent responses are the number of URLs extracted from each search result
                                            this.progress.increment();
                                            if (Array.isArray(res3)) {
                                                res3.forEach( c => options['urls_extracted'] += Number(c) );
                                            } else {
                                                options['urls_extracted'] += Number(res3);
                                            }
                                        }
                                    },
                                    error: (err3: unknown) => {
                                        console.log('err3',err3);
                                        this.stopProgressMeter();
                                        this.close(false);
                                    },
                                    complete: () => {
                                        if (options['fullAuto']) {
                                            options['viewURLs'] = false;
                                            options['viewAttempts'] = true;
                                            // ///////////////////////////////////////////
                                            this.resetProgressMeter($localize`Verifying URLs...`);
                                            this.subscriptions.push(this.net.request(
                                                'open-ils.url_verify',
                                                'open-ils.url_verify.session.verify',
                                                this.auth.token(),
                                                this.sessionId
                                            // eslint-disable-next-line rxjs-x/no-nested-subscribe
                                            ).subscribe({
                                                next: (res4) => {
                                                    console.log('res4',res4);
                                                    this.progress.update({max: res4['url_count'], value: res4['total_processed']});
                                                    options['verified_total_processed'] = Number(res4['total_processed']);
                                                },
                                                error: (err4: unknown) => {
                                                    this.stopProgressMeter();
                                                    console.log('err4',err4);
                                                    this.close(false);
                                                },
                                                complete: () => {
                                                    this.nameCollision = true;
                                                    this.stopProgressMeter();
                                                    this.close(options);
                                                }
                                            }));
                                        } else {
                                            this.nameCollision = true;
                                            this.stopProgressMeter();
                                            this.close(options);
                                        }
                                    }
                                }));
                            }
                        })
                    );
                }
            },
            error: (err: unknown) => {
                console.error('session.create error',err);
                this.fail.open();
                this.stopProgressMeter();
                this.close(false);
            },
            complete: () => {}
        }));
    }

    createUrlSelectors(): Observable<any> {
        // Examples:
        //* [@tag='856']/*[@code='u']
        //* [@tag='956']/*[@code='a' or @code='b' or @code='c']
        console.log('createUrlSelectors');
        let xpaths: string[] = [];
        let selectors: IdlObject[] = [];
        for (let i = 0; i < this.selectorModels['tag'].length; i++) {
            const tag = this.selectorModels['tag'][i];
            const subfields = this.selectorModels['subfields'][i];
            // eslint-disable-next-line max-len
            const xpath = '//*[@tag=\'' + tag + '\']/*[' + subfields.split('').map( (e: string) => '@code=\'' + e + '\'' ).join(' or ') + ']';
            xpaths.push(xpath);
        }
        xpaths = Array.from( new Set( xpaths ) ); // dedupe
        selectors = xpaths.map( _xpath => {
            const uvus = this.idl.create('uvus');
            uvus.isnew(true);
            uvus.session(this.sessionId);
            uvus.xpath( _xpath );
            return uvus;
        });
        return this.pcrud.create(selectors);
    }

}

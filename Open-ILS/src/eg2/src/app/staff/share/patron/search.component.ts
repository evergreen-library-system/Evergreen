import {Component, Input, Output, OnInit, AfterViewInit,
    EventEmitter, ViewChild} from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, of, from} from 'rxjs';
import {map, concatMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {PatronMergeDialogComponent} from './merge-dialog.component';
import {FormatService} from '@eg/core/format.service';
import {LocaleService} from '@eg/core/locale.service';

const DEFAULT_SORT = [
    'family_name ASC',
    'first_given_name ASC',
    'second_given_name ASC',
    'dob DESC'
];

const DEFAULT_FLESH = [
    'card', 'settings', 'standing_penalties', 'addresses', 'billing_address',
    'mailing_address', 'stat_cat_entries', 'waiver_entries', 'usr_activity',
    'notes', 'profile'
];

// const EXPAND_FORM = 'eg.circ.patron.search.show_extras';
const SHOW_NAMES = 'eg.circ.patron.search.show_names';
const SHOW_IDS = 'eg.circ.patron.search.show_ids';
const SHOW_ADDRESS = 'eg.circ.patron.search.show_address';
const INCLUDE_INACTIVE = 'eg.circ.patron.search.include_inactive';

export interface PatronSearchField {
    value: any;
    group?: number;
}

export interface PatronSearchFieldSet {
    [field: string]: PatronSearchField;
}

export interface PatronSearch {
    search: PatronSearchFieldSet;
    orgId?: number;
}

@Component({
    selector: 'eg-patron-search',
    templateUrl: './search.component.html',
    styleUrls: ['search.component.css']
})

export class PatronSearchComponent implements OnInit, AfterViewInit {

    @ViewChild('searchGrid') searchGrid: GridComponent;
    @ViewChild('addToBucket') addToBucket: BucketDialogComponent;
    @ViewChild('mergeDialog') mergeDialog: PatronMergeDialogComponent;

    startWithFired = false;
    @Input() startWithSearch: PatronSearch;

    // If set, load a batch of patrons by ID.
    @Input() patronIds: number[];

    // Only allow guaranteed-visible fields to be focused by default.
    // Options are the DOM ids directly: 'card', 'family_name', 'first_given_name',
    // 'profile_group', and 'home_ou' (Home Library). Default to 'family_name'.
    @Input() autofocusField: 'card' | 'family_name' | 'first_given_name' | 'profile_group' | 'home_ou' = 'family_name';

    // Fires on dbl-click or Enter while one or more search result
    // rows are selected.
    @Output() patronsActivated: EventEmitter<any>;

    // Fires when the selection of search result rows changes.
    // Emits an array of patron IDs
    @Output() selectionChange: EventEmitter<number[]>;

    // Fired with each search that is run, except for
    // any searches run as a result of @Input() startWithSearch.
    @Output() searchFired: EventEmitter<PatronSearch>;

    // Fired when the search form is cleared via the Clear Form button.
    @Output() formCleared: EventEmitter<void> = new EventEmitter<void>();

    search: any = {};
    searchOrg: IdlObject;
    show_names: boolean;
    show_ids: boolean;
    show_address: boolean;

    dataSource: GridDataSource;
    profileGroups: IdlObject[] = [];

    constructor(
        private route: ActivatedRoute,
        private net: NetService,
        public org: OrgService,
        private auth: AuthService,
        private store: ServerStoreService,
        private format: FormatService,
        public locale: LocaleService
    ) {
        this.patronsActivated = new EventEmitter<any>();
        this.selectionChange = new EventEmitter<number[]>();
        this.searchFired = new EventEmitter<PatronSearch>();

        this.dataSource = new GridDataSource();
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.getRows(pager, sort);
        };
    }

    ngOnInit() {

        this.route.queryParamMap.subscribe((params: ParamMap) => {
            const search = params.get('search');
            if (search) {
                try {
                    this.startWithSearch = {search: JSON.parse(search)};
                } catch (E) {
                    console.error('Invalid JSON search value', search, E);
                }
            }
        });

        this.searchOrg = this.org.root();

        this.store.getItemBatch([SHOW_NAMES, SHOW_IDS, SHOW_ADDRESS, INCLUDE_INACTIVE])
            .then(settings => {
                this.show_names = settings[SHOW_NAMES];
                this.show_ids = settings[SHOW_IDS];
                this.show_address = settings[SHOW_ADDRESS];
                this.search.inactive = settings[INCLUDE_INACTIVE];
            });
        this.search.inactive = true;
    }

    ngAfterViewInit() {
        requestAnimationFrame(() => {
            const el = document.getElementById(this.autofocusField) as HTMLElement | null;
            el.focus();
        });
    }

    toggleNameFields() {
        if (this.show_names) { // value set by ngModel
            this.store.setItem(SHOW_NAMES, true);
        } else {
            this.store.removeItem(SHOW_NAMES);
        }
    }

    toggleAddressFields() {
        if (this.show_address) { // value set by ngModel
            this.store.setItem(SHOW_ADDRESS, true);
        } else {
            this.store.removeItem(SHOW_ADDRESS);
        }
    }

    toggleIDFields() {
        if (this.show_ids) { // value set by ngModel
            this.store.setItem(SHOW_IDS, true);
        } else {
            this.store.removeItem(SHOW_IDS);
        }
    }

    toggleIncludeInactive() {
        if (this.search.inactive) { // value set by ngModel
            this.store.setItem(INCLUDE_INACTIVE, true);
        } else {
            this.store.removeItem(INCLUDE_INACTIVE);
        }
    }

    gridSelectionChange(keys: string[]) {
        this.selectionChange.emit(keys.map(k => Number(k)));
    }

    rowsActivated(rows: IdlObject | IdlObject[]) {
        this.patronsActivated.emit([].concat(rows));
    }

    getSelected(): IdlObject[] {
        return this.searchGrid ?
            this.searchGrid.context.getSelectedRows() : [];
    }

    go() {
        this.searchGrid.reload();
    }

    clear() {
        this.search = {profile: null};
        this.searchGrid.reload();
        this.formCleared.emit();
    }

    getRows(pager: Pager, sort: any[]): Observable<any> {

        let observable: Observable<IdlObject>;

        if (this.patronIds && !this.startWithFired) {
            observable = this.searchById(this.patronIds);
            this.startWithFired = true;
        } else if (this.search.id) {
            observable = this.searchById([this.search.id]);
        } else {
            observable = this.searchByForm(pager, sort);
        }

        return observable.pipe(map(user => this.localFleshUser(user)));
    }

    localFleshUser(user: IdlObject): IdlObject {
        user.home_ou(this.org.get(user.home_ou()));
        return user;
    }

    // Absorb a patron search object into the search form.
    absorbPatronSearch(pSearch: PatronSearch) {

        if (pSearch.orgId) {
            this.searchOrg = this.org.get(pSearch.orgId);
        }

        Object.keys(pSearch.search).forEach(field => {
            this.search[field] = pSearch.search[field].value;
        });
    }

    searchByForm(pager: Pager, sort: any[]): Observable<IdlObject> {

        if (this.startWithSearch && !this.startWithFired) {
            this.absorbPatronSearch(this.startWithSearch);
        }

        // Never fire a "start with" search after any search has fired
        this.startWithFired = true;

        const search = this.compileSearch();
        if (!search) { return of(); }

        const sorter = this.compileSort(sort);

        const pSearch: PatronSearch = {
            search: search,
            orgId: this.searchOrg.id()
        };

        this.searchFired.emit(pSearch);

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced.fleshed',
            this.auth.token(),
            pSearch.search,
            pager.limit,
            sorter,
            this.search.inactive,
            pSearch.orgId,
            DEFAULT_FLESH,
            pager.offset
        );
    }

    searchById(patronIds: number[]): Observable<IdlObject> {
        return from(patronIds).pipe(concatMap(id => {
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.fleshed.retrieve',
                this.auth.token(), id, DEFAULT_FLESH
            );
        }));
    }

    compileSort(sort: any[]): string[] {
        if (!sort || sort.length === 0) { return DEFAULT_SORT; }
        return sort.map(def => `${def.name} ${def.dir}`);
    }

    compileSearch(): PatronSearchFieldSet {

        let hasSearch = false;
        const search: PatronSearchFieldSet = {};

        Object.keys(this.search).forEach(field => {
            if (field === 'inactive') { return; }
            search[field] = this.mapSearchField(field);
            if (search[field] !== null) {
                hasSearch = true;
            } else {
                delete search[field];
            }
        });

        return hasSearch ? search : null;
    }

    isValue(val: any): boolean {
        return (val !== null && val !== undefined && val !== '');
    }

    mapSearchField(field: string): PatronSearchField {

        const value = this.search[field];
        if (!this.isValue(value)) { return null; }

        const chunk: PatronSearchField = {value: value, group: 0};

        switch (field) {

            case 'name': // name keywords
                delete chunk.group;
                break;

            case 'street1':
            case 'street2':
            case 'city':
            case 'state':
            case 'post_code':
                chunk.group = 1;
                break;

            case 'phone':
            case 'ident':
                chunk.group = 2;
                break;

            case 'card':
                chunk.group = 3;
                break;

            case 'profile':
                chunk.group = 5;
                chunk.value = chunk.value.id(); // pgt object
                break;

            case 'dob_day':
            case 'dob_month':
            case 'dob_year':
                chunk.group = 4;
                chunk.value = chunk.value.replace(/\D/g, '');

                if (!field.match(/year/)) {
                    // force day/month to be 2 digits
                    // eslint-disable-next-line no-magic-numbers
                    chunk.value = ('0' + value).slice(-2);
                }
                break;
        }

        // Confirm the value wasn't scrubbed away above
        if (!this.isValue(chunk.value)) { return null; }

        return chunk;
    }

    addSelectedToBucket(rows: IdlObject[]) {
        this.addToBucket.itemIds = rows.map(r => r.id());
        this.addToBucket.open().subscribe();
    }

    mergePatrons(rows: IdlObject[]) {
        this.mergeDialog.patronIds = [rows[0].id(), rows[1].id()];
        this.mergeDialog.open({size: 'lg'}).subscribe(changes => {
            if (changes) { this.searchGrid.reload(); }
        });
    }
}


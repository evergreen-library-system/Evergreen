import {Component, Input, Output, OnInit, AfterViewInit,
    EventEmitter, ViewChild, Renderer2} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';

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

const EXPAND_FORM = 'eg.circ.patron.search.show_extras';
const INCLUDE_INACTIVE = 'eg.circ.patron.search.include_inactive';

@Component({
  selector: 'eg-patron-search',
  templateUrl: './search.component.html'
})

export class PatronSearchComponent implements OnInit, AfterViewInit {

    @ViewChild('searchGrid', {static: false}) searchGrid: GridComponent;

    // Fired on dbl-click of a search result row.
    @Output() patronsSelected: EventEmitter<any>;

    // Fired on single click of a search results row
    @Output() patronsClicked: EventEmitter<any>;

    search: any = {};
    searchOrg: IdlObject;
    expandForm: boolean;
    dataSource: GridDataSource;
    profileGroups: IdlObject[] = [];

    constructor(
        private renderer: Renderer2,
        private net: NetService,
        public org: OrgService,
        private auth: AuthService,
        private store: ServerStoreService
    ) {
        this.patronsSelected = new EventEmitter<any>();
        this.patronsClicked = new EventEmitter<any>();
        this.dataSource = new GridDataSource();
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.getRows(pager, sort);
        };
    }

    ngOnInit() {
        this.searchOrg = this.org.root();
        this.store.getItemBatch([EXPAND_FORM, INCLUDE_INACTIVE])
            .then(settings => {
                this.expandForm = settings[EXPAND_FORM];
                this.search.inactive = settings[INCLUDE_INACTIVE];
            });
    }

    ngAfterViewInit() {
        this.renderer.selectRootElement('#focus-this-input').focus();
    }

    toggleExpandForm() {
        this.expandForm = !this.expandForm;
        if (this.expandForm) {
            this.store.setItem(EXPAND_FORM, true);
        } else {
            this.store.removeItem(EXPAND_FORM);
        }
    }

    toggleIncludeInactive() {
        if (this.search.inactive) { // value set by ngModel
            this.store.setItem(INCLUDE_INACTIVE, true);
        } else {
            this.store.removeItem(INCLUDE_INACTIVE);
        }
    }

    rowsSelected(rows: IdlObject | IdlObject[]) {
        this.patronsSelected.emit([].concat(rows));
    }

    rowsClicked(rows: IdlObject | IdlObject[]) {
        this.patronsClicked.emit([].concat(rows));
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
    }

    getRows(pager: Pager, sort: any[]): Observable<any> {

        let observable: Observable<IdlObject>;

        if (this.search.id) {
            observable = this.searchById();
        } else {
            observable = this.searchByForm(pager, sort);
        }

        return observable.pipe(map(user => this.localFleshUser(user)));
    }

    localFleshUser(user: IdlObject): IdlObject {
        user.home_ou(this.org.get(user.home_ou()));
        return user;
    }

    searchByForm(pager: Pager, sort: any[]): Observable<IdlObject> {

        const search = this.compileSearch();
        if (!search) { return of(); }

        const sorter = this.compileSort(sort);

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced.fleshed',
            this.auth.token(),
            this.compileSearch(),
            pager.limit,
            sorter,
            null, // ?
            this.searchOrg.id(),
            DEFAULT_FLESH,
            pager.offset
        );
    }

    searchById(): Observable<IdlObject> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), this.search.id, DEFAULT_FLESH
        );
    }

    compileSort(sort: any[]): string[] {
        if (!sort || sort.length === 0) { return DEFAULT_SORT; }
        return sort.map(def => `${def.name} ${def.dir}`);
    }

    compileSearch(): any {

        let hasSearch = false;
        const search: Object = {};

        Object.keys(this.search).forEach(field => {
            search[field] = this.mapSearchField(field);
            if (search[field]) { hasSearch = true; }
        });

        return hasSearch ? search : null;
    }

    isValue(val: any): boolean {
        return (val !== null && val !== undefined && val !== '');
    }

    mapSearchField(field: string): any {

        const value = this.search[field];
        if (!this.isValue(value)) { return null; }

        const chunk = {value: value, group: 0};

        switch (field) {

            case 'name': // name keywords
            case 'inactive':
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
                    chunk[field].value = ('0' + value).slice(-2);
                }
                break;
        }

        // Confirm the value wasn't scrubbed away above
        if (!this.isValue(chunk.value)) { return null; }

        return chunk;
    }
}


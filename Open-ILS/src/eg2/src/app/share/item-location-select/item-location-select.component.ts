import {Component, OnInit, AfterViewInit, Input, Output, ViewChild,
    EventEmitter, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';
import {Observable, from, of} from 'rxjs';
import {map, switchMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationService} from './item-location-select.service';

/**
 * Item (Copy) Location Selector.
 *
 * <eg-item-location-select [(ngModel)]="myAcplId"
    [contextOrgId]="anOrgId" permFilter="ADMIN_STUFF">
 * </eg-item-location-select>
 */

@Component({
    selector: 'eg-item-location-select',
    templateUrl: './item-location-select.component.html',
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => ItemLocationSelectComponent),
        multi: true
    }]
})
export class ItemLocationSelectComponent
implements OnInit, AfterViewInit, ControlValueAccessor {
    static domIdAuto = 0;

    // Limit copy locations to those owned at or above org units where
    // the user has work permissions for the provided permission code.
    @Input() permFilter: string;

    // Limit copy locations to those owned at or above this org unit.
    private _contextOrgId: number;
    @Input() set contextOrgId(value: number) {
        this._contextOrgId = value;
        this.ngOnInit();
    }

    // ... though if includeDescendants is true, shelving
    // locations at the descendants of the context OU are
    // also included; this is a special case for the
    // carousels editor
    @Input() set includeDescendants(value: boolean) {
        this._includeDescendants = value;
        this.ngOnInit();
    }
    get includeDescendants(): boolean {
        return this._includeDescendants;
    }

    get contextOrgId(): number {
        return this._contextOrgId;
    }

    // Load locations for multiple context org units.
    private _contextOrgIds = [];
    private _includeDescendants = false;
    @Input() set contextOrgIds(value: number[]) {
        this._contextOrgIds = value;
    }

    get contextOrgIds(): number[] {
        return this._contextOrgIds;
    }

    @Input() orgUnitLabelField = 'shortname';

    // Emits an acpl object or null on combobox value change
    @Output() valueChange: EventEmitter<IdlObject>;
    // Emits the combobox entry or null on value change
    @Output() entryChange: EventEmitter<ComboboxEntry>;

    @Input() required: boolean;

    @Input() domId = 'eg-item-location-select-' +
        ItemLocationSelectComponent.domIdAuto++;

    // If false, selector will be click-able
    @Input() loadAsync = false;

    @Input() disabled = false;

    // Display the selected value as text instead of within
    // the typeahead
    @Input() readOnly = false;

    // See combobox
    @Input() startsWith = false;

    // Show <Unset> when no value is applied.
    // This only applies to non-required fields, since <Unset> would
    // trick the combobox into thinking a valid value had been applied
    @Input() showUnsetString = true;

    // Optionally override the <Unset> string
    @Input() unsetString = $localize`<Unset>`;

    // Optionally provide an aria-labelledby for the input.  This should be one or more
    // space-delimited ids of elements that describe this item-location-select.
    @Input() ariaLabelledby: string;

    @ViewChild('comboBox', {static: false}) comboBox: ComboboxComponent;

    @Input() startId: number = null;
    filterOrgs: number[] = [];
    filterOrgsApplied = false;

    initDone = false; // true after first data load
    propagateChange = (id: number) => {};
    propagateTouch = () => {};

    getLocationsAsyncHandler = term => this.getLocationsAsync(term);

    constructor(
        private org: OrgService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService,
        private loc: ItemLocationService
    ) {
        this.valueChange = new EventEmitter<IdlObject>();
        this.entryChange = new EventEmitter<ComboboxEntry>();
    }

    ngOnInit() {
        if (this.loadAsync) {
            this.initDone = true;
        } else {
            this.setFilterOrgs()
                .then(_ => this.getLocations())
                .then(_ => this.initDone = true);
        }
    }

    ngAfterViewInit() {

        // Format the display of locations to include the org unit
        this.comboBox.formatDisplayString = (result: ComboboxEntry) => {
            let display = result.label || result.id;
            display = (display + '').trim();
            if (result.userdata) {
                display += ' (' +
                    this.orgName(result.userdata.owning_lib()) + ')';
            }
            return display;
        };
    }

    getLocations(): Promise<any> {

        if (this.filterOrgs.length === 0) {
            this.comboBox.entries = [];
            return Promise.resolve();
        }

        const search: any = {deleted: 'f'};

        if (this.startId) {
            // Guarantee we have the load-time copy location, which
            // may not be included in the org-scoped set of locations
            // we fetch by default.
            search['-or'] = [
                {id: this.startId},
                {owning_lib: this.filterOrgs}
            ];
        } else {
            search.owning_lib = this.filterOrgs;
        }

        const entries: ComboboxEntry[] = [];

        if (!this.required && this.showUnsetString) {
            entries.push({id: null, label: this.unsetString});
        }

        return this.pcrud.search('acpl', search, {order_by: {acpl: 'name'}}
        ).pipe(map(loc => {
            this.loc.locationCache[loc.id()] = loc;
            entries.push({id: loc.id(), label: loc.name(), userdata: loc});
        })).toPromise().then(_ => {
            this.comboBox.entries = entries;
        });
    }

    getLocationsAsync(term: string): Observable<ComboboxEntry> {
        // "1" is ignored, but a value is needed for pipe() below
        let obs = of([1]);

        if (!this.filterOrgsApplied) {
            // Apply filter orgs the first time they are needed.
            obs = from(this.setFilterOrgs());
        }

        return obs.pipe(switchMap(_ => this.getLocationsAsync2(term)));
    }

    getLocationsAsync2(term: string): Observable<ComboboxEntry> {

        if (this.filterOrgs.length === 0) {
            return of();
        }

        const ilike = this.startsWith ? `${term}%` : `%${term}%`;

        const search: any = {
            deleted: 'f',
            name: {'ilike': ilike}
        };

        if (this.startId) {
            // Guarantee we have the load-time copy location, which
            // may not be included in the org-scoped set of locations
            // we fetch by default.
            search['-or'] = [
                {id: this.startId},
                {owning_lib: this.filterOrgs}
            ];
        } else {
            search.owning_lib = this.filterOrgs;
        }

        return new Observable<ComboboxEntry>(observer => {
            if (!this.required && this.showUnsetString) {
                observer.next({id: null, label: this.unsetString});
            }

            this.pcrud.search('acpl', search, {order_by: {acpl: 'name'}}
            ).subscribe(
                loc => {
                    this.loc.locationCache[loc.id()] = loc;
                    observer.next({id: loc.id(), label: loc.name(), userdata: loc});
                },
                (err: unknown) => {},
                () => observer.complete()
            );
        });
    }


    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }

    cboxChanged(entry: ComboboxEntry) {
        const id = entry ? entry.id : null;
        this.propagateChange(id);
        this.valueChange.emit(id ? this.loc.locationCache[id] : null);
        this.entryChange.emit(entry ? entry : null);
        this.propagateTouch();
    }

    writeValue(id: number) {
        if (this.initDone) {
            this.getOneLocation(id).then(_ => this.comboBox.selectedId = id);
        } else {
            this.startId = id;
        }
    }

    getOneLocation(id: number) {
        if (!id) { return Promise.resolve(); }

        const promise = this.loc.locationCache[id] ?
            Promise.resolve(this.loc.locationCache[id]) :
            this.pcrud.retrieve('acpl', id).toPromise();

        return promise.then(loc => {

            this.loc.locationCache[loc.id()] = loc;
            const entry: ComboboxEntry = {
                id: loc.id(), label: loc.name(), userdata: loc};

            if (this.comboBox.entries) {
                this.comboBox.entries.push(entry);
            } else {
                this.comboBox.entries = [entry];
            }
        });
    }

    setFilterOrgs(): Promise<number[]> {
        let contextOrgIds: number[] = [];

        if (this.contextOrgIds.length) {
            contextOrgIds = this.contextOrgIds;
        } else {
            contextOrgIds = [this.contextOrgId || this.auth.user().ws_ou()];
        }

        let orgIds = [];
        contextOrgIds.forEach(id => orgIds = orgIds.concat(this.org.ancestors(id, true)));
        if (this.includeDescendants) {
            contextOrgIds.forEach(id => orgIds = orgIds.concat(this.org.descendants(id, true)));
        }

        this.filterOrgsApplied = true;

        if (!this.permFilter) {
            return Promise.resolve(this.filterOrgs = [...new Set(orgIds)]);
        }

        const orgsFromCache = this.loc.filterOrgsCache[this.permFilter];
        if (orgsFromCache && !this._contextOrgId) {
            // if we're using contextOrgId, it may well change, so
            // don't use the cache
            return Promise.resolve(this.filterOrgs = orgsFromCache);
        }

        return this.perm.hasWorkPermAt([this.permFilter], true)
            .then(values => {
            // Include ancestors of perm-approved org units (shared item locations)

                const permOrgIds = values[this.permFilter];
                let trimmedOrgIds = [];
                permOrgIds.forEach(orgId => {
                    if (orgIds.includes(orgId)) {
                        trimmedOrgIds = trimmedOrgIds.concat(this.org.ancestors(orgId, true));
                        if (this.includeDescendants) {
                            trimmedOrgIds = trimmedOrgIds.concat(this.org.descendants(orgId, true));
                        }
                    }
                });

                this.filterOrgs = [...new Set(trimmedOrgIds)];
                this.loc.filterOrgsCache[this.permFilter] = this.filterOrgs;

                return this.filterOrgs;
            });
    }

    orgName(orgId: number): string {
        return this.org.get(orgId)[this.orgUnitLabelField]();
    }
}




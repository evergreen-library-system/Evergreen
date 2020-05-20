import {Component, OnInit, AfterViewInit, Input, Output, ViewChild,
    EventEmitter, forwardRef} from '@angular/core';
import {ControlValueAccessor, FormGroup, FormControl, NG_VALUE_ACCESSOR} from '@angular/forms';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {StringComponent} from '@eg/share/string/string.component';

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

    // Limit copy locations to those owned at or above org units where
    // the user has work permissions for the provided permission code.
    @Input() permFilter: string;

    // Limit copy locations to those owned at or above this org unit.
    @Input() contextOrgId: number;

    @Input() orgUnitLabelField = 'shortname';

    // Emits an acpl object or null on combobox value change
    @Output() valueChange: EventEmitter<IdlObject>;

    @Input() required: boolean;

    @ViewChild('comboBox', {static: false}) comboBox: ComboboxComponent;
    @ViewChild('unsetString', {static: false}) unsetString: StringComponent;

    startId: number = null;
    filterOrgs: number[] = [];
    cache: {[id: number]: IdlObject} = {};

    initDone = false; // true after first data load
    propagateChange = (id: number) => {};
    propagateTouch = () => {};

    constructor(
        private org: OrgService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService
    ) {
        this.valueChange = new EventEmitter<IdlObject>();
    }

    ngOnInit() {
        this.setFilterOrgs()
        .then(_ => this.getLocations())
        .then(_ => this.initDone = true);
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

        if (!this.required) {
            entries.push({id: null, label: this.unsetString.text});
        }

        return this.pcrud.search('acpl', search, {order_by: {acpl: 'name'}}
        ).pipe(map(loc => {
            this.cache[loc.id()] = loc;
            entries.push({id: loc.id(), label: loc.name(), userdata: loc});
        })).toPromise().then(_ => {
            this.comboBox.entries = entries;
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
        this.valueChange.emit(id ? this.cache[id] : null);
    }

    writeValue(id: number) {
        if (this.initDone) {
            this.getOneLocation(id).then(_ => this.comboBox.selectedId = id);
        } else {
            this.startId = id;
        }
    }

    getOneLocation(id: number) {
        if (!id || this.cache[id]) { return Promise.resolve(); }

        return this.pcrud.retrieve('acpl', id).toPromise()
        .then(loc => {
            this.cache[loc.id()] = loc;
            this.comboBox.entries.push(
                {id: loc.id(), label: loc.name(), userdata: loc});
        });
    }

    setFilterOrgs(): Promise<number[]> {
        if (this.permFilter) {
            return this.perm.hasWorkPermAt([this.permFilter], true)
                .then(values => this.filterOrgs = values[this.permFilter]);
        }

        const org = this.contextOrgId || this.auth.user().ws_ou();
        this.filterOrgs = this.org.ancestors(this.contextOrgId, true);

        return Promise.resolve(this.filterOrgs);
    }

    orgName(orgId: number): string {
        return this.org.get(orgId)[this.orgUnitLabelField]();
    }
}




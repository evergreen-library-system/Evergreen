import {Component, OnInit, Input, Output, ViewChild, EventEmitter, forwardRef} from '@angular/core';
import {ControlValueAccessor, FormGroup, FormControl, NG_VALUE_ACCESSOR} from '@angular/forms';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

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
export class ItemLocationSelectComponent implements OnInit, ControlValueAccessor {

    // Limit copy locations to those owned at or above org units where
    // the user has work permissions for the provided permission code.
    @Input() permFilter: string;

    // Limit copy locations to those owned at or above this org unit.
    @Input() contextOrgId: number;

    @Input() orgUnitLabelField = 'shortname';

    // Emits an acpl object or null on combobox value change
    @Output() valueChange: EventEmitter<IdlObject>;

    @ViewChild('comboBox', {static: false}) comboBox: ComboboxComponent;

    startId: number = null;
    filterOrgs: number[];
    cache: {[id: number]: IdlObject} = {};

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
        this.setFilterOrgs().then(_ => this.getLocations());
    }

    getLocations(): Promise<any> {
        const entries: ComboboxEntry[] = [];
        const search = {owning_lib: this.filterOrgs, deleted: 'f'};

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
        if (this.comboBox) { // May not yet be initialized
            this.comboBox.selectedId = id;
        } else if (id) {
            this.startId = id;
        }
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




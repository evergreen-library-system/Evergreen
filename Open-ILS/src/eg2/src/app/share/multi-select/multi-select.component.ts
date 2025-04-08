/**
 * <eg-multi-select idlClass="acpl" linkedLibraryLabel="owning_lib" idlKey="id">
 * </eg-multi-select>
 */
import { Component, OnInit, Input, Output, EventEmitter } from '@angular/core';
import { map } from 'rxjs';
import { StoreService } from '@eg/core/store.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-multi-select',
    templateUrl: './multi-select.component.html',
    styles: [`
    .icons {margin-inline-start:-18px}
    .material-icons {font-size: 16px;font-weight:bold}
  `]
})
export class MultiSelectComponent implements OnInit {

    selected: ComboboxEntry;
    entrylist: ComboboxEntry[];

    @Input() idlClass: string;
    @Input() idlBaseQuery: any = null;
    @Input() idlKey: string;
    @Input() idlLabel: string;
    @Input() linkedLibraryLabel: string;
    @Input() startValue: string;
    // eslint-disable-next-line no-magic-numbers
    @Input() domId: string = 'MSC-' + Number(Math.random() * 10000);
    @Input() disabled = false;

    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onChange: EventEmitter<string>;

    acplContextOrgId: number;
    acplIncludeDescendants: boolean;

    constructor(
        private store: StoreService,
        private pcrud: PcrudService,
        private org: OrgService,
        private idl: IdlService,
    ) {
        this.entrylist = [];
        this.onChange = new EventEmitter<string>();
    }

    valueSelected(entry: ComboboxEntry) {
        if (entry) {
            this.selected = entry;
        } else {
            this.selected = null;
        }
    }

    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }

    addSelectedValue() {
        // special case to format the label
        if (this.idlClass === 'acpl' && this.selected.userdata) {
            this.selected.label =
                this.selected.userdata.name() + ' (' +
                this.getOrgShortname(this.selected.userdata.owning_lib()) + ')';
        }
        this.entrylist.push(this.selected);
        this.onChange.emit(this.compileCurrentValue());
    }
    removeValue(entry: ComboboxEntry) {
        this.entrylist = this.entrylist.filter(ent => ent.id !== entry.id);
        this.onChange.emit(this.compileCurrentValue());
    }

    compileCurrentValue(): string {
        const valstr = this.entrylist.map(entry => entry.id).join(',');
        return '{' + valstr + '}';
    }

    ngOnInit() {
        if (!this.idlKey) {
            if (this.idlClass) {
                this.idlKey = this.idl.classes[this.idlClass].pkey || 'id';
            } else {
                this.idlKey = 'id';
            }
        }

        if (!this.idlLabel) {
            if (this.idlClass) {
                this.idlLabel = this.idl.getClassSelector(this.idlClass) || 'name';
            } else {
                this.idlLabel = 'name';
            }
        }

        if (this.startValue && this.startValue !== '{}') {
            let valstr = this.startValue;
            valstr = valstr.replace(/^{/, '');
            valstr = valstr.replace(/}$/, '');
            const ids = valstr.split(',');
            const searchHash = {};
            searchHash[this.idlKey] = ids;
            const extra_args = {};
            if (this.linkedLibraryLabel) {
                const flesh_fields: Object = {};
                flesh_fields[this.idlClass] = [this.linkedLibraryLabel];
                extra_args['flesh'] = 1;
                extra_args['flesh_fields'] = flesh_fields;
                this.pcrud.search(this.idlClass, searchHash, extra_args).pipe(map(data => {
                    this.entrylist.push({
                        'id': data[this.idlKey](),
                        'label': data[this.idlLabel]() + ' (' + data[this.linkedLibraryLabel]().shortname() + ')'
                    });
                })).toPromise();
            } else {
                this.pcrud.search(this.idlClass, searchHash, extra_args).pipe(map(data => {
                    this.entrylist.push({ 'id': data[this.idlKey](), 'label': data[this.idlLabel]() });
                })).toPromise();
            }
        }
    }

}



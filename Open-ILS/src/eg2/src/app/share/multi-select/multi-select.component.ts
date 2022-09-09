/**
 * <eg-multi-select idlClass="acpl" linkedLibraryLabel="owning_lib" idlKey="id">
 * </eg-multi-select>
 */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter, ElementRef} from '@angular/core';
import {map} from 'rxjs/operators';
import {Observable, of, Subject} from 'rxjs';
import {StoreService} from '@eg/core/store.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationSelectComponent} from '@eg/share/item-location-select/item-location-select.component';

@Component({
  selector: 'eg-multi-select',
  templateUrl: './multi-select.component.html',
  styles: [`
    .icons {margin-left:-18px}
    .material-icons {font-size: 16px;font-weight:bold}
  `]
})
export class MultiSelectComponent implements OnInit {

    selected: ComboboxEntry;
    entrylist: ComboboxEntry[];

    @Input() idlClass: string;
    @Input() idlBaseQuery: any = null;
    @Input() idlKey: string;
    @Input() linkedLibraryLabel: string;
    @Input() startValue: string;

    @Output() onChange: EventEmitter<string>;

    acplContextOrgId: number;
    acplIncludeDescendants: boolean;

    constructor(
      private store: StoreService,
      private pcrud: PcrudService,
      private org: OrgService,
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
            this.idlKey = 'id';
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
                flesh_fields[this.idlClass] = [ this.linkedLibraryLabel ];
                extra_args['flesh'] = 1;
                extra_args['flesh_fields'] = flesh_fields;
                this.pcrud.search(this.idlClass, searchHash, extra_args).pipe(map(data => {
                    this.entrylist.push({
                        'id' : data.id(),
                        'label' : data.name() + ' (' + data[this.linkedLibraryLabel]().shortname() + ')'
                    });
                })).toPromise();
            } else {
                this.pcrud.search(this.idlClass, searchHash, extra_args).pipe(map(data => {
                    this.entrylist.push({ 'id' : data.id(), 'label' : data.name() });
                })).toPromise();
            }
        }
    }

}



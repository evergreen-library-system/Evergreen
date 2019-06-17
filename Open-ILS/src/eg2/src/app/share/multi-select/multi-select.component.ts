/**
 * <eg-multi-select idlClass="acpl" linkedLibraryLabel="owning_lib">
 * </eg-multi-select>
 */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter, ElementRef} from '@angular/core';
import {map} from 'rxjs/operators';
import {Observable, of, Subject} from 'rxjs';
import {StoreService} from '@eg/core/store.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

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
    @Input() linkedLibraryLabel: string;
    @Input() startValue: string;

    @Output() onChange: EventEmitter<string>;

    constructor(
      private store: StoreService,
      private pcrud: PcrudService,
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
    addSelectedValue() {
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
        if (this.startValue && this.startValue !== '{}') {
            let valstr = this.startValue;
            valstr = valstr.replace(/^{/, '');
            valstr = valstr.replace(/}$/, '');
            const ids = valstr.split(',');
            const extra_args = {};
            if (this.linkedLibraryLabel) {
                const flesh_fields: Object = {};
                flesh_fields[this.idlClass] = [ this.linkedLibraryLabel ];
                extra_args['flesh'] = 1;
                extra_args['flesh_fields'] = flesh_fields;
                this.pcrud.search(this.idlClass, { 'id' : ids }, extra_args).pipe(map(data => {
                    this.entrylist.push({
                        'id' : data.id(),
                        'label' : data.name() + ' (' + data[this.linkedLibraryLabel]().shortname() + ')'
                    });
                })).toPromise();
            } else {
                this.pcrud.search(this.idlClass, { 'id' : ids }, extra_args).pipe(map(data => {
                    this.entrylist.push({ 'id' : data.id(), 'label' : data.name() });
                })).toPromise();
            }
        }
    }

}



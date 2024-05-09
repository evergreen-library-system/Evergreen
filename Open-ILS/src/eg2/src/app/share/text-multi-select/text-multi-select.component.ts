/**
 * <eg-text-multi-select (onChange)="handler($event)"></eg-multi-select> // $event is an array
 */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter, ViewChildren, QueryList, ElementRef} from '@angular/core';
import {map} from 'rxjs/operators';
import {Observable, of, Subject} from 'rxjs';

@Component({
    selector: 'eg-text-multi-select',
    templateUrl: './text-multi-select.component.html',
    styles: [`
    .icons {margin-left:-18px}
    .material-icons {font-size: 16px;font-weight:bold}
    .eg-text-multi-select-row { display: grid; grid-template-columns: 1fr min-content; gap: .75rem; }
  `]
})
export class TextMultiSelectComponent implements OnInit {

    selected: string;
    entrylist: string[];

    @Input() startValue: Array<string>;
    // eslint-disable-next-line no-magic-numbers
    @Input() domId: string = 'TMSC-' + Number(Math.random() * 10000);
    @Input() disabled = false;

    @Output() onChange: EventEmitter<string[]>;

    @ViewChildren('newEntryInput') NewEntry: QueryList<ElementRef>;

    constructor(
    ) {
        this.entrylist = [];
        this.onChange = new EventEmitter<string[]>();
    }

    valueSelected(entry: any) {
        if (entry) {
            this.selected = entry;
        } else {
            this.selected = null;
        }
    }
    addSelectedValue() {
        if (this.selected) {
            this.entrylist.push(this.selected);
            this.selected = null;
        }
        this.NewEntry.toArray()[0].nativeElement.value = '';
        this.onChange.emit([...this.entrylist]);
    }
    removeValue(entry: any) {
        this.entrylist = this.entrylist.filter(ent => ent !== entry);
        this.onChange.emit([...this.entrylist]);
    }

    ngOnInit() {
        this.entrylist = [];
        if (this.startValue && this.startValue.length) {
            this.entrylist = [...this.startValue];
        }
    }

}



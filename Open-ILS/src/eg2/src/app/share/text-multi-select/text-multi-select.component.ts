/**
 * <eg-text-multi-select (onChange)="handler($event)"></eg-multi-select> // $event is an array
 */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter, ElementRef} from '@angular/core';
import {map} from 'rxjs/operators';
import {Observable, of, Subject} from 'rxjs';

@Component({
  selector: 'eg-text-multi-select',
  templateUrl: './text-multi-select.component.html',
  styles: [`
    .icons {margin-left:-18px}
    .material-icons {font-size: 16px;font-weight:bold}
  `]
})
export class TextMultiSelectComponent implements OnInit {

    selected: string;
    entrylist: string[];

    @Input() startValue: Array<string>;

    @Output() onChange: EventEmitter<string[]>;

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
        }
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



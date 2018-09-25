import {Component, Input, Host, OnInit} from '@angular/core';
import {ComboboxComponent} from './combobox.component';

@Component({
  selector: 'eg-combobox-entry',
  template: '<ng-template></ng-template>'
})
export class ComboboxEntryComponent implements OnInit {

    @Input() entryId: any;
    @Input() entryLabel: string;
    @Input() selected: boolean;

    constructor(@Host() private combobox: ComboboxComponent) {}

    ngOnInit() {
        if (this.selected) {
            this.combobox.startId = this.entryId;
        }
        this.combobox.addEntry(
            {id: this.entryId, label: this.entryLabel});
    }
}



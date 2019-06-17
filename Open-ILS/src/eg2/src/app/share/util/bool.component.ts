import {Component, Input} from '@angular/core';

/* Simple component to render a boolean value as human-friendly text */

@Component({
    selector: 'eg-bool',
    template: `
      <ng-container>
        <span *ngIf="value" class="badge badge-success" i18n>Yes</span>
        <span *ngIf="value == false" class="badge badge-secondary" i18n>No</span>
        <ng-container *ngIf="value === null">
          <span *ngIf="ternary" class="badge badge-light" i18n>Unset</span>
          <span *ngIf="!ternary"> </span>
      </ng-container>`
})
export class BoolDisplayComponent {

    _value: boolean;
    @Input() set value(v: any) {
        if (typeof v === 'string') {
            if (v === 't') {
                this._value = true;
            } else if (v === 'f') {
                this._value = false;
            } else {
                this._value = null;
            }
        } else {
            this._value = v;
        }
    }
    get value(): any {
        return this._value;
    }

    // If true, a null value displays as unset.
    // If false, a null value displays as an empty string.
    _ternary: boolean;
    @Input() set ternary(t: boolean) {
        this._ternary = t;
    }
    get ternary(): boolean {
        return this._ternary;
    }

    constructor() {
        this.value = null;
    }
}


import {Component, Input, OnInit, OnDestroy} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {Subject, takeUntil} from 'rxjs';

/**
 * MARC Fixed Field Editing Component
 */

@Component({
    selector: 'eg-fixed-field',
    templateUrl: './fixed-field.component.html'
})

export class FixedFieldComponent implements OnInit, OnDestroy {

    @Input() fieldCode: string;
    @Input() fieldLabel: string;
    @Input() context: MarcEditContext;
    /* eslint-disable no-magic-numbers */
    @Input() domId: any = 'ffld-' + Math.floor(Math.random() * 10000000);
    /* eslint-enable no-magic-numbers */

    get record(): MarcRecord { return this.context.record; }

    fieldMeta: IdlObject;
    fieldContent: string;
    private destroy$ = new Subject<void>();

    constructor() {}

    ngOnInit() {
        this.init().then(_ =>
            this.context.recordChange.pipe(takeUntil(this.destroy$))
                .subscribe(__ => this.init()));
    }

    init(): Promise<any> {
        if (!this.record) { return Promise.resolve(); }

        // If no field metadata is found for this fixed field code and
        // record type combo, the field will be hidden in the UI.
        return this.context.tagTable.getFfFieldMeta(this.fieldCode)
            .then(fieldMeta => {
                this.fieldMeta = fieldMeta;
                this.fieldContent = this.record.extractFixedField(this.fieldCode);
            });
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }

    separateCharacters() {
        if (!this.isMultiValue()) {
            return null;
        }

        return Array.from(this.fieldContent);
    }

    isMultiValue() {
        return this.record.isFixedFieldMultivalue(this.fieldCode);
    }
}



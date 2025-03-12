import { Component, Input } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';

@Component({
    selector: 'eg-copy-things-dialog',
    templateUrl: './copy-things-dialog-wrapper.component.html'
})
export class CopyThingsDialogWrapperComponent {
    @Input() thingType: string;
    @Input() copies: IdlObject[] = [];
    @Input() copyIds: number[] = [];
    @Input() batchWarningMessage: string;
    @Input() inBatch: () => boolean;
    @Input() onClose: () => void;
    @Input() onApplyChanges: () => void;

    constructor() {}
}

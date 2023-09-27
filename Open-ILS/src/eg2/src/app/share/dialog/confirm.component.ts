import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-confirm-dialog',
    templateUrl: './confirm.component.html'
})

/**
 * Confirmation dialog that asks a yes/no question.
 */
export class ConfirmDialogComponent extends DialogComponent {
    @Input() public hideFooter: boolean = false;
    @Input() public hideCancel: boolean = false;
    @Input() public confirmString: string = $localize`Confirm`;
    @Input() public cancelString: string = $localize`Cancel`;
    @Input() public dialogBody: string;
    @Input() public dialogBodyTemplate: TemplateRef<any>;
}



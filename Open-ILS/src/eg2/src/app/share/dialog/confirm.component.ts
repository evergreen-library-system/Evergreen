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
    @Input() public hideFooter = false;
    @Input() public hideCancel = false;
    @Input() public confirmString: string = $localize`Confirm`;
    @Input() public cancelString: string = $localize`Cancel`;
    @Input() public dialogTitle: string;
    @Input() public dialogBody: string;
    @Input() public dialogBodyTemplate: TemplateRef<any>;
    // This is not actually used within the template, but is here so that existing
    // code that references an eg-alert-dialog selector as a ConfirmDialogComponent
    // continues to work without needing to change.
    @Input() public alertType: 'success' | 'info' | 'warning' | 'danger' = 'danger';
}



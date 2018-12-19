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
    // What question are we asking?
    @Input() public dialogBody: string;
    @Input() public dialogBodyTemplate: TemplateRef<any>;
}



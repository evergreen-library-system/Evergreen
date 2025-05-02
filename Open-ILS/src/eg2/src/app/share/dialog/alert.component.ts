import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-alert-dialog',
    templateUrl: './alert.component.html',
    styles: ['.modal-alert.modal-body:is(:focus, :focus-visible) { outline: 0.25rem solid var(--bs-border-color-translucent); }']
})

/**
 * Alertation dialog that requests user input.
 */
export class AlertDialogComponent extends DialogComponent {

    // What are we warning the user with?
    @Input() public dialogTitle: string;
    @Input() public dialogBody: string;
    @Input() public dialogBodyTemplate: TemplateRef<any>;
    @Input() public alertType: 'success' | 'info' | 'warning' | 'danger' = 'danger';
}



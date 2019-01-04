import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
  selector: 'eg-alert-dialog',
  templateUrl: './alert.component.html'
})

/**
 * Alertation dialog that requests user input.
 */
export class AlertDialogComponent extends DialogComponent {

    // What are we warning the user with?
    @Input() public dialogBody: string;
}



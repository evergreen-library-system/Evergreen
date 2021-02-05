import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
  selector: 'eg-prompt-dialog',
  templateUrl: './prompt.component.html'
})

/**
 * Promptation dialog that requests user input.
 */
export class PromptDialogComponent extends DialogComponent {
    // What question are we asking?
    @Input() public dialogBody: string;
    // Value to return to the caller
    @Input() public promptValue: string;
    // 'password', etc.
    @Input() promptType = 'text';

    // May be used when promptType == 'number'
    @Input() promptMin: number = null;
    @Input() promptMax: number = null;
}



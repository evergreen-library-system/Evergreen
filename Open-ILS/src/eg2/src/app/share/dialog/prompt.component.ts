import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-prompt-dialog',
    templateUrl: './prompt.component.html'
})

/**
 * Promptation dialog that requests user input.
 */
export class PromptDialogComponent extends DialogComponent implements OnInit {
    static domId = 0;

    @Input() inputDomId = 'eg-prompt-dialog-' + PromptDialogComponent.domId++;

    // What question are we asking?
    @Input() public dialogBody: string;
    // Value to return to the caller
    @Input() public promptValue: string;
    // 'password', etc.
    @Input() promptType = 'text';
    @Input() confirmString: string = $localize`Confirm`;
    @Input() cancelString: string = $localize`Cancel`;

    // May be used when promptType == 'number'
    @Input() promptMin: number = null;
    @Input() promptMax: number = null;

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            const node = document.getElementById(this.inputDomId) as HTMLInputElement;
            if (node) { node.focus(); node.select(); }
        });
    }

    closeAndClear(value?: any) {
        this.close(value);
        this.promptValue = '';
    }
}



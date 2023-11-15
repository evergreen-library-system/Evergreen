import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

interface ClipboardValues {
    label: string;
    value: string;
}

@Component({
    selector: 'eg-clipboard-dialog',
    templateUrl: './clipboard-dialog.component.html'
})

/**
 * Copy To Clipboard dialog
 */
export class ClipboardDialogComponent extends DialogComponent {

    @Input() values: ClipboardValues[];

    copyValue(value: string) {

        const node =
            document.getElementById('clipboard-textarea') as HTMLTextAreaElement;

        // Un-hide the textarea just long enough to copy its data.
        // Using node.style instead of *ngIf for snappier show/hide.
        node.style.visibility = 'visible';
        node.style.display = 'block';
        node.value = value;
        node.focus();
        node.select();

        document.execCommand('copy');

        node.style.visibility = 'hidden';
        node.style.display = 'none';

        this.close();
    }
}



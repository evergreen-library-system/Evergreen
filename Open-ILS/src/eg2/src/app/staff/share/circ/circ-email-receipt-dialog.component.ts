import { Component } from '@angular/core';
import { DialogComponent } from '@eg/share/dialog/dialog.component';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { EmailReceiptData } from './circ.service';

@Component({
    selector: 'eg-circ-email-receipt-dialog',
    templateUrl: './circ-email-receipt-dialog.component.html'
})
export class CircEmailReceiptDialogComponent
    extends DialogComponent {

    options: EmailReceiptData[] = [];
    selected?: { patronId: number };

    constructor(private modal: NgbModal) { super(modal); }

    preventEnterOnSubmit(event: KeyboardEvent): void {
        const enterKeyCode = 13;
        if (event.key === 'Enter' || event.keyCode === enterKeyCode) {
            const tagName = (event.target as HTMLElement).tagName;
            if (tagName.toLowerCase() !== 'button') {
                event.preventDefault();
            }
        }
    }

    ok(): void {
        const selected = this.options.find(option =>
            option.patron.id() === this.selected?.patronId
        );
        if (!selected) { return; }
        this.close(selected);
    }
}

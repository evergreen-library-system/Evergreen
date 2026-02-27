
import { Component, Input, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { EdiAttrSetProvidersComponent } from './edi-attr-set-providers.component';

@Component({
    selector: 'eg-edi-attr-set-providers-dialog',
    templateUrl: './edi-attr-set-providers-dialog.component.html',
    imports: [
        EdiAttrSetProvidersComponent
    ]
})

export class EdiAttrSetProvidersDialogComponent
    extends DialogComponent {
    private modal: NgbModal;


    @Input() attrSetId: number;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }
}

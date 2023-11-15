import {Component, Input} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-edi-attr-set-providers-dialog',
    templateUrl: './edi-attr-set-providers-dialog.component.html'
})

export class EdiAttrSetProvidersDialogComponent
    extends DialogComponent {

    @Input() attrSetId: number;

    constructor(
        private modal: NgbModal
    ) {
        super(modal);
    }
}

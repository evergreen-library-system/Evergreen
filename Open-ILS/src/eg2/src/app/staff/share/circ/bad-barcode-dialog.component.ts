import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/** Bad Item Barcode Dialog */

@Component({
  templateUrl: 'bad-barcode-dialog.component.html',
  selector: 'eg-bad-barcode-dialog'
})
export class BadBarcodeDialogComponent extends DialogComponent {

    barcode: string;

    constructor(private modal: NgbModal) {
        super(modal);
    }
}



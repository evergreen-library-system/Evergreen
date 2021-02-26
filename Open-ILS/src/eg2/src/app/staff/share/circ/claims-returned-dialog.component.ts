import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {Observable, empty, of, from} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
  templateUrl: 'claims-returned-dialog.component.html',
  selector: 'eg-claims-returned-dialog'
})
export class ClaimsReturnedDialogComponent
    extends DialogComponent implements OnInit {

    barcodes: string[];
    returnDate: string;
    patronExceeds: boolean;

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.returnDate = new Date().toISOString()
            this.patronExceeds = false;
        });
    }

    modifyBatch() {
    }

    confirmExceeds() {
    }
}



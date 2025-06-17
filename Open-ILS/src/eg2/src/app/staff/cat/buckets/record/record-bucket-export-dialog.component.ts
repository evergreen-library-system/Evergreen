import {Component, Input} from '@angular/core';
import {FormGroup, FormControl, Validators} from '@angular/forms';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-record-bucket-export-dialog',
    templateUrl: './record-bucket-export-dialog.component.html'
})

export class RecordBucketExportDialogComponent extends DialogComponent {

    recordFormat = 'USMARC';
    encoding = 'UTF-8';
    includeItems = false;

    onSubmit() {
        this.close({
            recordFormat: this.recordFormat,
            encoding: this.encoding,
            includeItems: this.includeItems
        });
    }

    constructor(
        private modal: NgbModal,
    ) {
        super(modal);
    }
}


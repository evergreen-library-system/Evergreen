import {Component, OnInit, Input,
    Output, EventEmitter} from '@angular/core';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-circ-matrix-matchpoint-dialog',
    templateUrl: './circ-matrix-matchpoint-dialog.component.html'
})
export class CircMatrixMatchpointDialogComponent extends DialogComponent implements OnInit {

    // Emit the modified object when the save action completes.
    @Output() recordSaved = new EventEmitter<any>();

    // Emit the original object when the save action is canceled.
    @Output() recordCanceled = new EventEmitter<any>();

    constructor(
        private modal: NgbModal // required for passing to parent
        ) {
        super(modal);
      }

    ngOnInit() {
    }

    open(args?: NgbModalOptions): Observable<any> {
        if (!args) {
            args = {};
        }
        // ensure we don't hang on to our copy of the record
        // if the user dismisses the dialog
        args.beforeDismiss = () => {
            return true;
        };
        return super.open(args);
    }

    cancel() {
        this.recordCanceled.emit();
        this.close();
    }

    closeEditor() {
        this.recordCanceled.emit();
        this.close();
    }

    save() {
        this.recordSaved.emit();
    }
}

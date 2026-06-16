import {Component, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

/* Dialog for modifying circulation due dates. */

@Component({
    selector: 'eg-due-date-dialog',
    templateUrl: 'due-date-dialog.component.html'
})

export class DueDateDialogComponent extends DialogComponent {

    @Input() circs: IdlObject[] = [];
    @Input() isRenewal = false;

    protected dueDateIso = new Date().toISOString();
    protected nowTime = new Date().getTime();

    constructor(
        private modal: NgbModal, // required for passing to parent
    ) {
        super(modal); // required for subclassing
    }

    open(options?: NgbModalOptions): Observable<any> {
        const now = new Date();
        // floor minutes to be compatible with the time picker so
        // our "now" time isn't slightly ahead in dueDateChange()
        now.setSeconds(0, 0);
        this.nowTime = now.getTime();

        this.dueDateIso = this.isRenewal || this.circs.length !== 1
            ? new Date().toISOString()
            : this.circs[0].due_date();

        return super.open(options);
    }

    protected dueDateChange(iso: string): void {
        if (iso && (!this.isRenewal || Date.parse(iso) > this.nowTime)) {
            this.dueDateIso = iso;
        } else {
            this.dueDateIso = null;
        }
    }
}

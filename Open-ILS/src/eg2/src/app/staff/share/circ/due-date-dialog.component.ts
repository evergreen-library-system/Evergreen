import {Component, Input} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DateTimeSelectComponent} from '@eg/share/datetime-select/datetime-select.component';
import {Observable} from 'rxjs';

/* Dialog for modifying circulation due dates. */

@Component({
    selector: 'eg-due-date-dialog',
    templateUrl: 'due-date-dialog.component.html',
    imports: [DateTimeSelectComponent]
})

export class DueDateDialogComponent extends DialogComponent {

    @Input() circs: IdlObject[] = [];
    @Input() isRenewal = false;

    protected dueDateIso = new Date().toISOString();
    protected nowTime = new Date().getTime();

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

import {Component, Input, ViewChild} from '@angular/core';
import {from, Observable, tap, concatMap} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for marking items discard.
 */

@Component({
    selector: 'eg-mark-discard-dialog',
    templateUrl: 'mark-discard-dialog.component.html'
})

export class MarkDiscardDialogComponent
    extends DialogComponent {

    @Input() copyIds: number[];

    numSucceeded: number;
    numFailed: number;

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    open(args: NgbModalOptions): Observable<boolean> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        return super.open(args);
    }

    markOneItemDiscard(id: number): Observable<any> {

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.mark_item_discard',
            this.auth.token(), id
        ).pipe(tap(result => {
            if (Number(result) === 1) {
                this.numSucceeded++;
                this.successMsg.current().then(str => this.toast.success(str));
            } else {
                this.numFailed++;
                console.error('Mark discard failed ', this.evt.parse(result));
                this.errorMsg.current().then(str => this.toast.warning(str));
            }
        }));
    }

    markItemsDiscard(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;

        return from(this.copyIds)
            .pipe(concatMap(copyId => this.markOneItemDiscard(copyId)))
            .toPromise().then(_ => this.close(this.numSucceeded > 0));
    }
}




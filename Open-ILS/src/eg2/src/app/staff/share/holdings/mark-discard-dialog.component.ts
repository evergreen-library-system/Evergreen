import { Component, Input, ViewChild, inject } from '@angular/core';
import {from, Observable, tap, concatMap} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import { CommonModule } from '@angular/common';


/**
 * Dialog for marking items discard.
 */

@Component({
    selector: 'eg-mark-discard-dialog',
    templateUrl: 'mark-discard-dialog.component.html',
    imports: [
        CommonModule,
        StringComponent
    ]
})

export class MarkDiscardDialogComponent
    extends DialogComponent {
    private modal: NgbModal;
    private toast = inject(ToastService);
    private net = inject(NetService);
    private evt = inject(EventService);
    private auth = inject(AuthService);


    @Input() copyIds: number[];

    numSucceeded: number;
    numFailed: number;

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;

    constructor() {
        const modal = inject(NgbModal);

        super(modal); // required for subclassing

        this.modal = modal;
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




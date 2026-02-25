import { Component, Input, ViewChild, inject } from '@angular/core';
import {Observable} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import { CommonModule } from '@angular/common';


/**
 * Dialog for marking items missing.
 */

@Component({
    selector: 'eg-mark-missing-dialog',
    templateUrl: 'mark-missing-dialog.component.html',
    imports: [
        CommonModule,
        StringComponent
    ]
})

export class MarkMissingDialogComponent
    extends DialogComponent {
    private modal: NgbModal;
    private toast = inject(ToastService);
    private net = inject(NetService);
    private evt = inject(EventService);
    private auth = inject(AuthService);


    @Input() copyIds: number[];

    numSucceeded: number;
    numFailed: number;

    @ViewChild('successMsg', { static: true })
    private successMsg: StringComponent;

    @ViewChild('errorMsg', { static: true })
    private errorMsg: StringComponent;

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

    async markOneItemMissing(ids: number[]): Promise<any> {
        if (ids.length === 0) {
            return Promise.resolve();
        }

        const id = ids.pop();

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.mark_item_missing',
            this.auth.token(), id
        ).toPromise().then(async(result) => {
            if (Number(result) === 1) {
                this.numSucceeded++;
                this.toast.success(await this.successMsg.current());
            } else {
                this.numFailed++;
                console.error('Mark missing failed ', this.evt.parse(result));
                this.toast.warning(await this.errorMsg.current());
            }
            return this.markOneItemMissing(ids);
        });
    }

    async markItemsMissing(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        const ids = [].concat(this.copyIds);
        await this.markOneItemMissing(ids);
        this.close(this.numSucceeded > 0);
    }
}




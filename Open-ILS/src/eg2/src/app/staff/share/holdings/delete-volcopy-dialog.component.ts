import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {Observable, throwError} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EgEvent, EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';


/**
 * Dialog that confirms, then deletes items and call numbers
 */

@Component({
  selector: 'eg-delete-holding-dialog',
  templateUrl: 'delete-volcopy-dialog.component.html'
})

export class DeleteHoldingDialogComponent
    extends DialogComponent implements OnInit {

    // List of "acn" objects which may contain copies.
    // Objects of either type marked "isdeleted" will be deleted.
    @Input() callNums: IdlObject[];

    // If true, just ask the server to delete all attached copies
    // for any deleted call numbers.
    // Note if this is true and a call number is provided that does not
    // contain its fleshed copies, the number of copies to delete will not be
    // reported correctly.
    @Input() forceDeleteCopies: boolean;

    numCallNums: number;
    numCopies: number;
    numSucceeded: number;
    numFailed: number;
    deleteEventDesc: string;

    @ViewChild('successMsg', { static: true })
        private successMsg: StringComponent;

    @ViewChild('errorMsg', { static: true })
        private errorMsg: StringComponent;

    @ViewChild('confirmOverride', {static: false})
        private confirmOverride: ConfirmDialogComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private renderer: Renderer2,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    open(args: NgbModalOptions): Observable<boolean> {
        this.numCallNums = 0;
        this.numCopies = 0;
        this.numSucceeded = 0;
        this.numFailed = 0;

        this.callNums.forEach(callNum => {
            if (callNum.isdeleted()) {
                this.numCallNums++;
            }
            if (Array.isArray(callNum.copies())) {
                callNum.copies().forEach(c => {
                    if (c.isdeleted() || this.forceDeleteCopies) {
                        // Marking copies deleted in forceDeleteCopies mode
                        // is not required, but we do it here so we can
                        // report the number of copies to be deleted.
                        c.isdeleted(true);
                        this.numCopies++;
                    }
                });
            }
        });

        if (this.numCallNums === 0 && this.numCopies === 0) {
            console.debug('Holdings delete called with no usable data');
            return throwError(false);
        }

        return super.open(args);
    }

    deleteHoldings(override?: boolean) {

        this.deleteEventDesc = '';

        const flags: any = {
            force_delete_copies: this.forceDeleteCopies
        };

        let method = 'open-ils.cat.asset.volume.fleshed.batch.update';
        if (override) {
            method = `${method}.override`;
            flags.events = ['TITLE_LAST_COPY', 'COPY_DELETE_WARNING'];
        }

        this.net.request(
            'open-ils.cat', method,
            this.auth.token(), this.callNums, 1, flags
        ).toPromise().then(
            result => {
                const evt = this.evt.parse(result);
                if (evt) {
                    this.handleDeleteEvent(evt, override);
                } else {
                    this.numSucceeded++;
                    this.close(this.numSucceeded > 0);
                }
            },
            err => {
                console.warn(err);
                this.errorMsg.current().then(msg => this.toast.warning(msg));
                this.numFailed++;
            }
        );
    }

    handleDeleteEvent(evt: EgEvent, override?: boolean): Promise<any> {

        if (override) { // override failed
            console.warn(evt);
            this.numFailed++;
            return this.errorMsg.current().then(msg => this.toast.warning(msg));
        }

        this.deleteEventDesc = evt.desc;

        return this.confirmOverride.open().toPromise().then(confirmed => {
            if (confirmed) {
                return this.deleteHoldings(true);

            } else {
                // User canceled the delete confirmation dialog
                this.numFailed++;
                this.errorMsg.current().then(msg => this.toast.warning(msg));
                this.close(this.numSucceeded > 0);
            }
        });
    }
}




import {Component, OnInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {Subscription} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';

/**
 * Dialog for making items bookable
 */

@Component({
    selector: 'eg-make-bookable-dialog',
    templateUrl: 'make-bookable-dialog.component.html'
})
export class MakeBookableDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    // Note copyIds must refer to copies that belong to a single
    // bib record.
    @Input() copyIds: number[];
    copies: IdlObject[];

    numSucceeded: number;
    numFailed: number;
    updateComplete: boolean;
    newResourceType: number;
    newResourceOrg: number;

    onOpenSub: Subscription;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {
        // eslint-disable-next-line rxjs-x/no-async-subscribe
        this.onOpenSub = this.onOpen$.subscribe(async () => {
            this.numSucceeded = 0;
            this.numFailed = 0;
            this.updateComplete = false;
        });
    }

    ngOnDestroy() {
        this.onOpenSub.unsubscribe();
    }

    manageUrlParams(): any {
        if (this.newResourceOrg) {
            return {
                gridFilters: JSON.stringify({type: this.newResourceType}),
                contextOrg: this.newResourceOrg
            };
        }
    }

    makeBookable() {
        this.newResourceType = null;

        this.net.request(
            'open-ils.booking',
            'open-ils.booking.resources.create_from_copies',
            this.auth.token(), this.copyIds
        ).toPromise().then(
            resp => {
                // resp.brsrc = [[brsrc.id, acp.id, existed], ...]
                // resp.brt = [[brt.id, brt.peer_record, existed], ...]
                const evt = this.evt.parse(resp);
                if (evt) { return Promise.reject(evt); }
                this.numSucceeded = resp.brsrc.length;
                this.newResourceType = resp.brt[0][0]; // new resource ID
                this.updateComplete = true;
                this.successMsg.current().then(msg => this.toast.success(msg));
            },
            err => Promise.reject(err)
        ).then(
            ok => {
                // Once resource creation is complete, grab the call number
                // for the first copy to get the owning library
                this.pcrud.retrieve('acp', this.copyIds[0],
                    {flesh: 1, flesh_fields: {acp: ['call_number']}})
                    .toPromise().then(copy => {
                        this.newResourceOrg = copy.call_number().owning_lib();
                        this.updateComplete = true;
                    });
            },
            err => {
                console.error(err);
                this.numFailed++;
                this.errorMsg.current().then(msg => this.toast.danger(msg));
                this.updateComplete = true;
            }
        );
    }
}




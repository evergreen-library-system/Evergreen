import {Component, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from, switchMap} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {BillingService} from '@eg/staff/share/billing/billing.service';

/**
 * Dialog for marking items damaged and asessing related bills.
 */

@Component({
    selector: 'eg-mark-damaged-dialog',
    templateUrl: 'mark-damaged-dialog.component.html'
})

export class MarkDamagedDialogComponent
    extends DialogComponent {

    @Input() copyId: number;

    // If the item is checked out, ask the API to check it in first.
    @Input() handleCheckin = false;

    copy: IdlObject;
    bibSummary: BibRecordSummary;
    billingTypes: ComboboxEntry[];

    // Overide the API suggested charge amount
    amountChangeRequested: boolean;
    newCharge: number;
    newNote: string;
    newBtype: number;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;


    // Charge data returned from the server requesting additional charge info.
    chargeResponse: any;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private billing: BillingService,
        private bib: BibRecordService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    /**
     * Fetch the item/record, then open the dialog.
     * Dialog promise resolves with true/false indicating whether
     * the mark-damanged action occured or was dismissed.
     */
    open(args: NgbModalOptions): Observable<boolean> {
        this.reset();

        if (!this.copyId) {
            return throwError('copy ID required');
        }

        // Map data-loading promises to an observable
        const obs = from(
            this.getBillingTypes().then(_ => this.getData()));

        // Fire data loading observable and replace results with
        // dialog opener observable.
        return obs.pipe(switchMap(_ => super.open(args)));
    }

    // Fetch-cache billing types
    getBillingTypes(): Promise<any> {
        return this.billing.getUserBillingTypes().then(types => {
            this.billingTypes =
                types.map(bt => ({id: bt.id(), label: bt.name()}));
        });
    }

    getData(): Promise<any> {
        return this.pcrud.retrieve('acp', this.copyId,
            {flesh: 1, flesh_fields: {acp: ['call_number']}}).toPromise()
            .then(copy => {
                this.copy = copy;
                return this.bib.getBibSummary(
                    copy.call_number().record()).toPromise();
            }).then(summary => {
                this.bibSummary = summary;
            });
    }

    reset() {
        this.copy = null;
        this.bibSummary = null;
        this.chargeResponse = null;
        this.newCharge = null;
        this.newNote = null;
        this.amountChangeRequested = false;
    }

    bTypeChange(entry: ComboboxEntry) {
        this.newBtype = entry.id;
    }

    markDamaged(args: any) {
        this.chargeResponse = null;

        if (args.apply_fines === 'apply') {
            args.override_amount = this.newCharge;
            args.override_btype = this.newBtype;
            args.override_note = this.newNote;
        }

        if (this.handleCheckin) {
            args.handle_checkin = true;
        }

        this.net.request(
            'open-ils.circ', 'open-ils.circ.mark_item_damaged',
            this.auth.token(), this.copyId, args
        ).subscribe(
            { next: result => {
                console.debug('Mark damaged returned', result);

                if (Number(result) === 1) {
                    this.successMsg.current().then(msg => this.toast.success(msg));
                    this.close(true);
                    return;
                }

                const evt = this.evt.parse(result);

                if (evt.textcode === 'DAMAGE_CHARGE') {
                    // More info needed from staff on how to hangle charges.
                    this.chargeResponse = evt.payload;
                    this.newCharge = this.chargeResponse.charge;
                }
            }, error: (err: unknown) => {
                this.errorMsg.current().then(m => this.toast.danger(m));
                console.error(err);
            } }
        );
    }
}


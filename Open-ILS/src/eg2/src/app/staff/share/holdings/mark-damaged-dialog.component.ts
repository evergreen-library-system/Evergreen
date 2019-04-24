import {Component, OnInit, Input, ViewChild} from '@angular/core';
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

/**
 * Dialog for marking items damaged and asessing related bills.
 */

@Component({
  selector: 'eg-mark-damaged-dialog',
  templateUrl: 'mark-damaged-dialog.component.html'
})

export class MarkDamagedDialogComponent
    extends DialogComponent implements OnInit {

    @Input() copyId: number;
    copy: IdlObject;
    bibSummary: BibRecordSummary;
    billingTypes: ComboboxEntry[];

    // Overide the API suggested charge amount
    amountChangeRequested: boolean;
    newCharge: number;
    newNote: string;
    newBtype: number;

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;


    // Charge data returned from the server requesting additional charge info.
    chargeResponse: any;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private bib: BibRecordService,
        private auth: AuthService) {
        super(modal); // required for subclassing
        this.billingTypes = [];
    }

    ngOnInit() {}

    /**
     * Fetch the item/record, then open the dialog.
     * Dialog promise resolves with true/false indicating whether
     * the mark-damanged action occured or was dismissed.
     */
    async open(args: NgbModalOptions): Promise<boolean> {
        this.reset();

        if (!this.copyId) {
            return Promise.reject('copy ID required');
        }

        await this.getBillingTypes();
        await this.getData();
        return super.open(args);
    }

    // Fetch-cache billing types
    async getBillingTypes(): Promise<any> {
        if (this.billingTypes.length > 1) {
            return Promise.resolve();
        }
        return this.pcrud.search('cbt',
            {owner: this.org.fullPath(this.auth.user().ws_ou(), true)},
            {}, {atomic: true}
        ).toPromise().then(bts => {
            this.billingTypes = bts
                .sort((a, b) => a.name() < b.name() ? -1 : 1)
                .map(bt => ({id: bt.id(), label: bt.name()}));
        });
    }

    async getData(): Promise<any> {
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

        if (args && args.apply_fines === 'apply') {
            args.override_amount = this.newCharge;
            args.override_btype = this.newBtype;
            args.override_note = this.newNote;
        }

        this.net.request(
            'open-ils.circ', 'open-ils.circ.mark_item_damaged',
            this.auth.token(), this.copyId, args
        ).subscribe(
            result => {
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
            },
            err => {
                this.errorMsg.current().then(m => this.toast.danger(m));
                console.error(err);
            }
        );
    }
}


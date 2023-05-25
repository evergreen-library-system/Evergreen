import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {Observable} from 'rxjs';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {LineitemService} from '../lineitem/lineitem.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
    selector: 'eg-acq-manage-claims-dialog',
    templateUrl: './manage-claims-dialog.component.html'
})

export class ManageClaimsDialogComponent extends DialogComponent {
    @Input() li: IdlObject;
    @Input() lidIds: number[];
    @Input() insideBatch: boolean;

    @ViewChild('printTemplate', { static: true }) private printTemplate: TemplateRef<any>;

    lidsWithClaims: IdlObject[] = [];

    note = '';
    claimEventTypes: number[] = [];
    selectedClaimEventTypes: number[] = [];
    claimType: ComboboxEntry;

    constructor(
        private modal: NgbModal,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        private liService: LineitemService
    ) { super(modal); }

    open(args?: NgbModalOptions): Observable<any> {
        if (!args) {
            args = {};
        }

        this.lidsWithClaims = this.getLidsWithClaims();
        this.note = '';
        this.claimEventTypes = [];
        this.selectedClaimEventTypes = [];
        this.getClaimEventTypes();

        // console.log('ManageClaimsDialogComponent, this.lidIds',this.lidIds);
        if (this.lidIds) {
            this.li.lineitem_details().forEach( (lid: IdlObject) => {
                // console.log('ManageClaimsDialogComponent, lid',lid);
                if (this.lidIds.includes( Number(lid.id()) )) {
                    lid._selected_for_claim = true;
                    // console.log('ManageClaimsDialogComponent, self-selecting',lid);
                } else {
                    lid._selected_for_claim = false;
                    // console.log('ManageClaimsDialogComponent, ensuring not selected',lid);
                }
            });
        }

        return super.open(args);
    }

    getLidsWithClaims(): IdlObject[] {
        return this.li.lineitem_details().filter(x => x.claims().length > 0);
    }

    getClaimEventTypes() {
        this.pcrud.retrieveAll('acqclet',
            { 'order_by': {'acqclet': 'code'}, flesh: 1, flesh_fields: {acqclet: ['org_unit']} },
            {}
        ).subscribe(t => this.claimEventTypes.push(t));
    }

    canPerformClaim(): boolean {
        if (!this.claimType) { return false; }
        if (!this.claimType.id) { return false; }
        const lidsToClaim = this.li.lineitem_details().filter(x => x._selected_for_claim);
        if (lidsToClaim.length < 1) { return false; }
        return true;
    }

    claimItems() {
        if (!this.canPerformClaim()) { return; }
        const lidsToClaim = this.li.lineitem_details()
            .filter(x => x._selected_for_claim)
            .map(x => x.id());
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.claim.lineitem_detail.atomic',
            this.auth.token(),
            lidsToClaim, null,
            this.claimType.id,
            this.note,
            null,
            this.selectedClaimEventTypes
        ).subscribe(result => {
            if (result && result.length) {
                const voucher = result.map(x => x.template_output().data()).join('<hr>');
                this.printer.print({
                    template: this.printTemplate,
                    contextData: { voucher: voucher },
                    printContext: 'default'
                });
            }
            this.close({claimMade: true});
        });
    }

    printVoucher(lidId: number) {
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.claim.voucher.by_lineitem_detail',
            this.auth.token(), lidId
        ).subscribe(result => {
            if (!result) { return; }
            this.printer.print({
                template: this.printTemplate,
                contextData: { voucher: result.template_output().data() },
                printContext: 'default'
            });
        });
    }
}

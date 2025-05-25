import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AuthService} from '@eg/core/auth.service';
import {ProviderRecord, ProviderRecordService} from './provider-record.service';

@Component({
    selector: 'eg-acq-provider-summary-pane',
    styleUrls: ['summary-pane.component.css'],
    templateUrl: './summary-pane.component.html'
})

export class AcqProviderSummaryPaneComponent implements OnInit, AfterViewInit {

    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;

    collapsed = false;

    provider_id = '';
    provider_name = '';
    provider_code = '';
    provider_owner = '';
    provider_currency_type = '';
    provider_holding_tag = '';
    provider_addresses = '';
    provider_san = '';
    provider_edi_default = '';
    provider_active = '';
    provider_prepayment_required = '';
    provider_url = '';
    provider_email = '';
    provider_phone = '';
    provider_fax_phone = '';
    provider_default_claim_policy = '';
    provider_default_copy_count = '';
    provider_contacts = '';
    provider_provider_notes = '';

    provider_id_label;
    provider_name_label;
    provider_code_label;
    provider_owner_label;
    provider_currency_type_label;
    provider_holding_tag_label;
    provider_addresses_label;
    provider_san_label;
    provider_edi_default_label;
    provider_active_label;
    provider_prepayment_required_label;
    provider_url_label;
    provider_email_label;
    provider_phone_label;
    provider_fax_phone_label;
    provider_default_claim_policy_label;
    provider_default_copy_count_label;
    provider_contacts_label;
    provider_provider_notes_label;

    @Input() providerId: any;
    @ViewChild('errorString', { static: true }) errorString: StringComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;
    @Output() summaryToggled: EventEmitter<boolean> = new EventEmitter<boolean>();

    provider: IdlObject;
    provRec: ProviderRecord;

    constructor(
        private router: Router,
        private pcrud: PcrudService,
        private idl: IdlService,
        private org: OrgService,
        private toast: ToastService,
        private auth: AuthService,
        private prov: ProviderRecordService,
    ) {}

    ngOnInit() {
        this.provider_id_label = this.idl.classes['acqpro'].field_map['id'].label;
        this.provider_name_label = this.idl.classes['acqpro'].field_map['name'].label;
        this.provider_code_label = this.idl.classes['acqpro'].field_map['code'].label;
        this.provider_owner_label = this.idl.classes['acqpro'].field_map['owner'].label;
        this.provider_currency_type_label = this.idl.classes['acqpro'].field_map['currency_type'].label;
        this.provider_holding_tag_label = this.idl.classes['acqpro'].field_map['holding_tag'].label;
        this.provider_addresses_label = this.idl.classes['acqpro'].field_map['addresses'].label;
        this.provider_san_label = this.idl.classes['acqpro'].field_map['san'].label;
        this.provider_edi_default_label = this.idl.classes['acqpro'].field_map['edi_default'].label;
        this.provider_active_label = this.idl.classes['acqpro'].field_map['active'].label;
        this.provider_prepayment_required_label = this.idl.classes['acqpro'].field_map['prepayment_required'].label;
        this.provider_url_label = this.idl.classes['acqpro'].field_map['url'].label;
        this.provider_email_label = this.idl.classes['acqpro'].field_map['email'].label;
        this.provider_phone_label = this.idl.classes['acqpro'].field_map['phone'].label;
        this.provider_fax_phone_label = this.idl.classes['acqpro'].field_map['fax_phone'].label;
        this.provider_default_claim_policy_label = this.idl.classes['acqpro'].field_map['default_claim_policy'].label;
        this.provider_default_copy_count_label = this.idl.classes['acqpro'].field_map['default_copy_count'].label;
        this.provider_contacts_label = this.idl.classes['acqpro'].field_map['contacts'].label;
        this.provider_provider_notes_label = this.idl.classes['acqpro'].field_map['provider_notes'].label;
    }

    ngAfterViewInit() {
        if (this.providerId) {
            this.update(this.providerId);
        }
    }

    update(newProvider: any) {
        function no_provider() {
            // FIXME: empty the pane or keep last summarized view?
            this.provider_id = '';
            this.provider_name = '';
            this.provider_code = '';
            this.provider_owner = '';
            this.provider_currency_type = '';
            this.provider_holding_tag = '';
            this.provider_addresses = '';
            this.provider_san = '';
            this.provider_edi_default = '';
            this.provider_active = '';
            this.provider_prepayment_required = '';
            this.provider_url = '';
            this.provider_email = '';
            this.provider_phone = '';
            this.provider_fax_phone = '';
            this.provider_default_claim_policy = '';
            this.provider_default_copy_count = '';
            this.provider_contacts = '';
            this.provider_provider_notes = '';
        }

        if (newProvider) {
            const providerRecord = this.prov.currentProviderRecord();
            const provider = providerRecord.record;
            if (provider) {
                this.provRec = providerRecord;
                this.provider = provider;
                this.provider_id = provider.id();
                this.provider_name = provider.name();
                this.provider_code = provider.code();
                this.provider_owner = this.org.get(provider.owner()).shortname();
                this.provider_currency_type = provider.currency_type() ? provider.currency_type().label() : '';
                this.provider_holding_tag = provider.holding_tag();
                this.provider_addresses = provider.addresses();
                this.provider_san = provider.san();
                if (typeof provider.edi_default() === 'object') {
                    this.provider_edi_default = provider.edi_default() ? provider.edi_default().label() : '';
                } else {
                    // not fleshed, presumably because user doesn't have
                    // permission to retrieve EDI accounts
                    this.provider_edi_default = '';
                }
                this.provider_active = provider.active();
                this.provider_prepayment_required = provider.prepayment_required();
                this.provider_url = provider.url();
                this.provider_email = provider.email();
                this.provider_phone = provider.phone();
                this.provider_fax_phone = provider.fax_phone();
                this.provider_default_claim_policy = provider.default_claim_policy();
                this.provider_default_copy_count = provider.default_copy_count();
                this.provider_contacts = provider.contacts();
                this.provider_provider_notes = provider.provider_notes();
            } else {
                this.provider = null;
                no_provider();
            }
        } else {
            no_provider();
        }
    }

    deleteProvider() {
        this.delConfirm.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.pcrud.remove(this.provider)
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                .subscribe(
                    { next: ok2 => {
                        this.deleteSuccessString.current()
                            .then(str => this.toast.success(str));
                        this.router.navigate(['/staff', 'acq', 'provider']);
                    }, error: (err: unknown) => {
                        this.errorString.current()
                            .then(str => this.toast.danger(str));
                    }, complete: ()  => {
                        console.debug('deleteProvider, what is this?');
                    } }
                );
        });

    }

    canDeleteProvider() {
        if (this.provider && this.provider.id()) {
            return this.provRec.canAdmin && this.provRec.canDelete;
        } else {
            return false;
        }
    }

    toggleCollapse() {
        this.collapsed = ! this.collapsed;
        this.summaryToggled.emit(this.collapsed);
    }

}

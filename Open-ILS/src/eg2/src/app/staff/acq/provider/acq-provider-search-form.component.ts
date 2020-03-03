import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute} from '@angular/router';
import {StaffCommonModule} from '@eg/staff/common.module';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {AcqProviderSearchTerm, AcqProviderSearch} from './acq-provider-search.service';
import {StoreService} from '@eg/core/store.service';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';

@Component({
  selector: 'eg-acq-provider-search-form',
  styleUrls: ['acq-provider-search-form.component.css'],
  templateUrl: './acq-provider-search-form.component.html'
})

export class AcqProviderSearchFormComponent implements OnInit, AfterViewInit {

    @Output() searchSubmitted = new EventEmitter<AcqProviderSearch>();

    collapsed = false;

    providerName = '';
    providerCode = '';
    providerOwners: OrgFamily;
    contactName = '';
    providerEmail = '';
    providerPhone = '';
    providerCurrencyType = '';
    providerSAN = '';
    providerEDIDefault = null;
    providerURL = '';
    providerIsActive = 'active';

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private localStore: StoreService,
        private idl: IdlService,
        private toast: ToastService,
        private auth: AuthService,
    ) {}

    ngOnInit() {
        const self = this;
        this.providerOwners = {primaryOrgId: this.auth.user().ws_ou(), includeDescendants: true};
        this.collapsed = this.localStore.getLocalItem('eg.acq.provider.search.collapse_form') || false;
    }

    ngAfterViewInit() {}

    clearSearch() {
        this.providerName = '';
        this.providerCode = '';
        this.providerOwners = {primaryOrgId: this.auth.user().ws_ou(), includeDescendants: true};
        this.contactName = '';
        this.providerEmail = '';
        this.providerPhone = '';
        this.providerCurrencyType = '';
        this.providerSAN = '';
        this.providerEDIDefault = null;
        this.providerURL = '';
        this.providerIsActive = 'active';
    }

    submitSearch() {

        const searchTerms: AcqProviderSearchTerm[] = [];
        if (this.providerName) {
            searchTerms.push({ classes: ['acqpro'], fields: ['name'], op: 'ilike', value: this.providerName });
        }
        if (this.providerCode) {
            searchTerms.push({ classes: ['acqpro'], fields: ['code'], op: 'ilike', value: this.providerCode });
        }
        if (this.providerOwners) {
            searchTerms.push({ classes: ['acqpro'], fields: ['owner'], op: 'in', value: this.providerOwners.orgIds });
        }
        if (this.contactName) {
            searchTerms.push({ classes: ['acqpc'], fields: ['name'], op: 'ilike', value: this.contactName });
        }
        if (this.providerEmail) {
            searchTerms.push({ classes: ['acqpro', 'acqpc'], fields: ['email', 'email'], op: 'ilike', value: this.providerEmail });
        }
        if (this.providerPhone) {
            // this requires the flesh hash to contain: { ... join: { acqpc: { type: 'left' } } ... }
            searchTerms.push({
                classes: ['acqpc', 'acqpro', 'acqpro'],
                fields: ['phone', 'phone', 'fax_phone'],
                op: 'ilike',
                value: this.providerPhone,
            });
        }
        if (this.providerCurrencyType) {
            searchTerms.push({ classes: ['acqpro'], fields: ['currency_type'], op: '=', value: this.providerCurrencyType });
        }
        if (this.providerSAN) {
            searchTerms.push({ classes: ['acqpro'], fields: ['san'], op: 'ilike', value: this.providerSAN });
        }
        if (this.providerEDIDefault) {
            searchTerms.push({ classes: ['acqpro'], fields: ['edi_default'], op: '=', value: this.providerEDIDefault });
        }
        if (this.providerURL) {
            searchTerms.push({ classes: ['acqpro'], fields: ['url'], op: 'ilike', value: this.providerURL });
        }
        switch (this.providerIsActive) {
            case 'active': {
                searchTerms.push({ classes: ['acqpro'], fields: ['active'], op: '=', value: 't' });
                break;
            }
            case 'inactive': {
                searchTerms.push({ classes: ['acqpro'], fields: ['active'], op: '=', value: 'f' });
                break;
            }
        }

        // tossing setTimeout here to ensure that the
        // grid data source is fully initialized
        setTimeout(() => {
            this.searchSubmitted.emit({
                terms: searchTerms,
            });
        });
    }

    toggleCollapse() {
        this.collapsed = ! this.collapsed;
        this.localStore.setLocalItem('eg.acq.provider.search.collapse_form', this.collapsed);
    }

}

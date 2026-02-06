import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AcqProviderRoutingModule} from './routing.module';
import {AcqProviderComponent} from './acq-provider.component';
import {AcqProviderSearchFormComponent} from './acq-provider-search-form.component';
import {AcqProviderSummaryPaneComponent} from './summary-pane.component';
import {ProviderResultsComponent} from './provider-results.component';
import {ProviderDetailsComponent} from './provider-details.component';
import {ProviderAddressesComponent} from './provider-addresses.component';
import {ProviderContactsComponent} from './provider-contacts.component';
import {ProviderContactAddressesComponent} from './provider-contact-addresses.component';
import {ProviderHoldingsComponent} from './provider-holdings.component';
import {ProviderAttributesComponent} from './provider-attributes.component';
import {ProviderEdiAccountsComponent} from './provider-edi-accounts.component';
import {ProviderInvoicesComponent} from './provider-invoices.component';
import {ProviderPurchaseOrdersComponent} from './provider-purchase-orders.component';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {ProviderRecordService} from './provider-record.service';

@NgModule({
    imports: [
        AcqProviderComponent,
        AcqProviderSearchFormComponent,
        AcqProviderSummaryPaneComponent,
        ProviderAddressesComponent,
        ProviderAttributesComponent,
        ProviderContactAddressesComponent,
        ProviderContactsComponent,
        ProviderHoldingsComponent,
        ProviderInvoicesComponent,
        ProviderPurchaseOrdersComponent,
        ProviderResultsComponent,
        StaffCommonModule,
        OrgFamilySelectModule,
        ProviderDetailsComponent,
        FmRecordEditorModule,
        AcqProviderRoutingModule,
        ProviderEdiAccountsComponent,
    ],
    providers: [
        ProviderRecordService
    ],
})

export class AcqProviderModule {
}

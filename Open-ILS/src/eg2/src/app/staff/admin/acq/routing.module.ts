import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminAcqSplashComponent} from './admin-acq-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';
import {ClaimingAdminComponent} from './claiming-admin.component';
import {FiscalYearAdminComponent} from './fiscal-year-admin.component';

const routes: Routes = [{
    path: 'splash',
    component: AdminAcqSplashComponent
}, {
    path: 'edi_account',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'acq',
        table: 'edi_account',
        fieldOrder: 'id,label,provider,owner,account,vendacct,vendcode,last_activity,host,username,password,path,in_dir,use_attrs,attr_set',
        readonlyFields: 'last_activity'
    }]
}, {
    path: 'claiming',
    component: ClaimingAdminComponent
}, {
    path: 'claim_event_type',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_policy',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_policy_action',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'claim_type',
    redirectTo: 'claiming' // from legacy auto-generated admin page
}, {
    path: 'currency',
    loadChildren: () =>
        import('./currency/currencies.module').then(m => m.CurrenciesModule)
}, {
    path: 'currency_type',
    redirectTo: 'currency' // from auto-generated admin page
}, {
    path: 'exchange_rate',
    redirectTo: 'currency' // from auto-generated admin page
}, {
    path: 'distribution_formula',
    loadChildren: () =>
        import('./distribution_formula/distribution-formulas.module').then(m => m.DistributionFormulasModule)
}, {
    path: 'edi_attr_set',
    loadChildren: () =>
        import('./edi_attr_set/edi-attr-sets.module').then(m => m.EdiAttrSetsModule)
}, {
    path: 'fiscal-year-admin',
    component: FiscalYearAdminComponent
}, {
    path:'fiscal_calendar',
    redirectTo: 'fiscal-year-admin' // from legacy auto-generated admin page
}, {
    path:'fiscal_year',
    redirectTo: 'fiscal-year-admin' // from legacy auto-generated admin page
}, {
    path: 'funds',
    loadChildren: () =>
        import('./funds/funds.module').then(m => m.FundsModule)
}, {
    path: 'fund',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_allocation',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_allocation_percent',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_debit',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'funding_source',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'funding_source_credit',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_tag',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_tag_map',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: 'fund_transfer',
    redirectTo: 'funds' // from auto-generated admin page
}, {
    path: ':table',
    component: BasicAdminPageComponent,
    // All ACQ admin pages cover data in the acq.* schema.  No need to
    // duplicate it within the URL path.  Pass it manually instead.
    data: [{schema: 'acq'}]
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class AdminAcqRoutingModule {}

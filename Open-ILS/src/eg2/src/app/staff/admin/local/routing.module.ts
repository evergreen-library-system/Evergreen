import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminLocalSplashComponent} from './admin-local-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';
import {AddressAlertComponent} from './address-alert.component';
import {AdminCarouselComponent} from './admin-carousel.component';
import {AdminStaffPortalPageComponent} from './staff_portal_page/staff-portal-page.component';
import {StandingPenaltyComponent} from './standing-penalty.component';
import {CourseTermMapComponent} from './course-reserves/course-term-map.component';

const routes: Routes = [{
    path: 'splash',
    component: AdminLocalSplashComponent
}, {
    path: 'config/hold_matrix_matchpoint',
    component: BasicAdminPageComponent,
    data: [{schema: 'config', table: 'hold_matrix_matchpoint', disableOrgFilter: true}]
}, {
    path: 'actor/address_alert',
    component: AddressAlertComponent
}, {
    path: 'asset/copy_location_order',
    loadChildren: () =>
      import('./copy-loc-order/copy-loc-order.module').then(m => m.CopyLocOrderModule)
}, {
    path: 'asset/copy_location',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'asset',
        table: 'copy_location',
        fieldOrder: 'owning_lib,name,opac_visible,circulate,holdable,hold_verify,checkin_alert,deleted,label_prefix,label_suffix,url,id'}]
}, {
    path: 'asset/shelving_location_groups',
    loadChildren: () =>
      import('./shelving_location_groups/shelving_location_groups.module').then(m => m.ShelvingLocationGroupsModule)
}, {
    path: 'container/carousel',
    component: AdminCarouselComponent
}, {
    path: 'asset/course_list',
    loadChildren: () =>
      import('./course-reserves/course-reserves.module').then(m => m.CourseReservesModule)
}, {
    path: 'asset/course_module_term_course_map',
    component: CourseTermMapComponent
}, {
    path: 'actor/search_filter_group',
    loadChildren: () =>
      import('./search-filter/search-filter-group.module').then(m => m.SearchFilterGroupModule)
}, {
    path: 'config/circ_limit_set',
    loadChildren: () =>
      import('./circ_limit_set/circ_limit_set.module').then(m => m.CircLimitSetModule)
}, {
    path: 'config/openathens_identity',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'config',
        table: 'openathens_identity',
        fieldOrder: 'id,org_unit,active,api_key,connection_id,connection_uri,auto_signon_enabled,auto_signout_enabled,' +
                    'unique_identifier,display_name,release_prefix,release_first_given_name,release_second_given_name,' +
                    'release_family_name,release_suffix,release_email,release_home_ou,release_barcode',
        defaultNewRecord: {
            active: true,
            auto_signon_enabled: true,
            unique_identifier: 1,
            display_name: 1
        }
    }]
}, {
    path: 'config/standing_penalty',
    component: StandingPenaltyComponent,
}, {
    path: 'asset/org_unit_settings',
    loadChildren: () =>
      import('./org-unit-settings/org-unit-settings.module').then(m => m.OrgUnitSettingsModule)
}, {
    path: 'config/ui_staff_portal_page_entry',
    component: AdminStaffPortalPageComponent
}, {
    path: 'action/survey',
    loadChildren: () =>
      import('./survey/survey.module').then(m => m.SurveyModule)
}, {
    path: 'action_trigger/event_definition',
    loadChildren: () =>
      import('./triggers/triggers.module').then(m => m.TriggersModule)
}, {
    path: 'config/idl_field_doc',
    loadChildren: () => import('./field-documentation/field-documentation.module')
      .then(m => m.FieldDocumentationModule)
}, {
    path: 'money/cash_reports',
    loadChildren: '@eg/staff/admin/local/cash-reports/cash-reports.module#CashReportsModule'
}, {
    path: 'negative-balances',
    loadChildren: () =>
      import('./negative-balances/negative-balances.module').then(m => m.NegativeBalancesModule)
}, {
    path: ':schema/:table',
    component: BasicAdminPageComponent
}

];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminLocalRoutingModule {}

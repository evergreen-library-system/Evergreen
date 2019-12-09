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
    data: [{
        schema: 'config',
        table: 'hold_matrix_matchpoint',
        disableOrgFilter: true,
        fieldOrder: 'description,active,item_owning_ou,item_circ_ou,circ_modifier,' +
          'marc_type,marc_form,marc_bib_level,marc_vr_format,ref_flag,item_age,' +
          'user_home_ou,usr_grp,stop_blocked_user,holdable,age_hold_protect_rule,' +
          'max_holds,include_frozen_holds,request_ou,pickup_ou,strict_ou_match,' +
          'transit_range,distance_is_from_owner,requestor_grp,id'
    }]
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
        enableUndelete: true,
        readonlyFields: 'deleted',
        initialFilterValues: {deleted: 'f'},
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
    path: 'rating/badge',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'rating',
        table: 'badge',
        fieldOrder: 'name,description,scope,weight,horizon_age,importance_age,importance_interval,' +
          'importance_scale,percentile,attr_filter,circ_mod_filter,src_filter,loc_grp_filter,' +
          'recalc_interval,fixed_rating,discard,last_calc,popularity_parameter'
    }]
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
    loadChildren: () =>
        import('./cash-reports/cash-reports.module').then(m => m.CashReportsModule)
}, {
    path: 'negative-balances',
    loadChildren: () =>
        import('./negative-balances/negative-balances.module').then(m => m.NegativeBalancesModule)
}, {
    path: 'config/circ_matrix_matchpoint',
    loadChildren: '@eg/staff/admin/local/circ_matrix_matchpoint/circ-matrix-matchpoint.module#CircMatrixMathpointModule'
}, {
    path: 'asset/stat_cat',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'asset',
        table: 'stat_cat',
        readonlyFields: 'id',
        orgDefaultAllowed: 'owner',
        orgFieldsDefaultingToContextOrg: 'owner',
        fieldOptions: {owner: {persistKey: 'admin.stat_cat.owner' } },
        contextOrgSelectorPersistKey: 'admin.item_stat_cat.main_org_selector',
        recordLabel: $localize `Statistical Category Editor - Item`,
        // eslint-disable-next-line max-len
        deleteConfirmation: $localize `Are you sure you wish to delete the selected statistical categories?  This will also remove the affected stat cats from any item records using them.`,
        fieldOrder: 'name,owner,required,opac_visible,checkout_archive,sip_field,sip_format'}]
}, {
    path: 'asset/stat_cat_entry',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'asset',
        table: 'stat_cat_entry',
        readonlyFields: 'id,stat_cat',
        orgDefaultAllowed: 'owner',
        orgFieldsDefaultingToContextOrg: 'owner',
        fieldOptions: {owner: {persistKey: 'admin.stat_cat.owner' } },
        contextOrgSelectorPersistKey: 'admin.item_stat_cat.main_org_selector',
        disableEdit: true,
        disableDelete: true,
        recordLabel: $localize `Statistical Category Entry - Item`,
        hideClearFilters: true,
        fieldOrder: 'stat_cat,value,owner'}]
}, {
    path: 'actor/stat_cat',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'actor',
        table: 'stat_cat',
        readonlyFields: 'id',
        orgDefaultAllowed: 'owner',
        orgFieldsDefaultingToContextOrg: 'owner',
        fieldOptions: {owner: {persistKey: 'admin.stat_cat.owner' } },
        contextOrgSelectorPersistKey: 'admin.patron_stat_cat.main_org_selector',
        recordLabel: $localize `Statistical Category Editor - Patron`,
        // eslint-disable-next-line max-len
        deleteConfirmation: $localize `Are you sure you wish to delete the selected statistical categories?  This will also remove the affected stat cats from any patron records using them.`,
        fieldOrder: 'name,owner,required,opac_visible,usr_summary,allow_freetext,checkout_archive,sip_field,sip_format'}]
}, {
    path: 'actor/stat_cat_entry',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'actor',
        table: 'stat_cat_entry',
        readonlyFields: 'id,stat_cat',
        orgDefaultAllowed: 'owner',
        orgFieldsDefaultingToContextOrg: 'owner',
        fieldOptions: {owner: {persistKey: 'admin.stat_cat.owner' } },
        contextOrgSelectorPersistKey: 'admin.patron_stat_cat.main_org_selector',
        disableEdit: true,
        disableDelete: true,
        recordLabel: $localize `Statistical Category Entry - Patron`,
        hideClearFilters: true,
        fieldOrder: 'stat_cat,value,owner'}]
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

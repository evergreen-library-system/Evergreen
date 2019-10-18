import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminLocalSplashComponent} from './admin-local-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';
import {AddressAlertComponent} from './address-alert.component';
import {AdminCarouselComponent} from './admin-carousel.component';
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
    path: 'asset/copy_location',
    component: BasicAdminPageComponent,
    data: [{
        schema: 'asset',
        table: 'copy_location',
        fieldOrder: 'owning_lib,name,opac_visible,circulate,holdable,hold_verify,checkin_alert,deleted,label_prefix,label_suffix,url,id'}]
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
    path: 'config/circ_limit_set',
    loadChildren: () =>
      import('./circ_limit_set/circ_limit_set.module').then(m => m.CircLimitSetModule)
}, {
    path: 'config/standing_penalty',
    component: StandingPenaltyComponent
}, {
    path: 'action/survey',
    loadChildren: () =>
      import('./survey/survey.module').then(m => m.SurveyModule)
}, {
    path: ':schema/:table',
    component: BasicAdminPageComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminLocalRoutingModule {}

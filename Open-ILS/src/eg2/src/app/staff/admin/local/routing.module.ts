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

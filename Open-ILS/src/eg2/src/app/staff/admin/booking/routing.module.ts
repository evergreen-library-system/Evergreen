import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AdminBookingSplashComponent} from './admin-booking-splash.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';

const routes: Routes = [{
    path: 'splash',
    component: AdminBookingSplashComponent
}, {
    path: 'resource_type',
    component: BasicAdminPageComponent,
    data: [{schema: 'booking', table: 'resource_type', readonlyFields: 'catalog_item,record'}]
}, {
    path: ':table',
    component: BasicAdminPageComponent,
    // All booking admin pages cover data in the booking.* schema.  No need to
    // duplicate it within the URL path.  Pass it manually instead.
    data: [{schema: 'booking'}]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AdminBookingRoutingModule {}

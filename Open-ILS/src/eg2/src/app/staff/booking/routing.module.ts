import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CreateReservationComponent} from './create-reservation.component';
import {ManageReservationsComponent} from './manage-reservations.component';
import {PickupComponent} from './pickup.component';
import {PullListComponent} from './pull-list.component';
import {ReturnComponent} from './return.component';

const routes: Routes = [{
  path: 'create_reservation',
    children: [
      {path: '', component: CreateReservationComponent},
      {path: 'for_patron/:patron_id', component: CreateReservationComponent},
      {path: 'for_resource/:resource_barcode', component: CreateReservationComponent},
  ]}, {
  path: 'manage_reservations',
    children: [
      {path: '', component: ManageReservationsComponent},
      {path: 'by_patron/:patron_id', component: ManageReservationsComponent},
      {path: 'by_resource/:resource_barcode', component: ManageReservationsComponent},
      {path: 'by_resource_type/:resource_type_id', component: ManageReservationsComponent},
  ]}, {
  path: 'pickup',
    children: [
      {path: '', component: PickupComponent},
      {path: 'by_patron/:patron_id', component: PickupComponent},
  ]}, {
  path: 'pull_list',
  component: PullListComponent
  }, {
  path: 'return',
    children: [
      {path: '', component: ReturnComponent},
      {path: 'by_patron/:patron_id', component: ReturnComponent},
  ]},
  ];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class BookingRoutingModule {}

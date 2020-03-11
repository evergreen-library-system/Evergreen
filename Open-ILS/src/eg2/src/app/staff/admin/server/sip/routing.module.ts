import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SipAccountListComponent} from './account-list.component';
import {SipAccountComponent} from './account.component';

const routes: Routes = [{
    path: '',
    component: SipAccountListComponent
}, {
    path: ':id',
    component: SipAccountComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class SipAccountRoutingModule {}


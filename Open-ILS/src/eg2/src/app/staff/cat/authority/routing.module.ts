import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AuthorityMarcEditComponent} from './marc-edit.component';
import {BrowseAuthorityComponent} from './browse.component';
import {ManageAuthorityComponent} from './manage.component';

const routes: Routes = [{
    path: 'edit',
    component: AuthorityMarcEditComponent
  }, {
    path: 'edit/:id',
    component: AuthorityMarcEditComponent
  }, {
    path: 'browse',
    component: BrowseAuthorityComponent
  }, {
    path: 'manage/:id/:tab',
    component: ManageAuthorityComponent
  }, {
    path: 'manage/:id/:tab',
    component: ManageAuthorityComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class AuthorityRoutingModule {}


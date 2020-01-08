import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AuthorityMarcEditComponent} from './marc-edit.component';

const routes: Routes = [{
    path: 'edit',
    component: AuthorityMarcEditComponent
  }, {
    path: 'edit/:id',
    component: AuthorityMarcEditComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class AuthorityRoutingModule {}


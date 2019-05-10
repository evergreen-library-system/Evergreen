import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {HopelessComponent} from './hopeless.component';

const routes: Routes = [{
  path: '',
  component: HopelessComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class HopelessRoutingModule {}

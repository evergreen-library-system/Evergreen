import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {MarcBatchComponent} from './marcbatch.component';

const routes: Routes = [{
    path: '',
    component: MarcBatchComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class MarcBatchRoutingModule {}


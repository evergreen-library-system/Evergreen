import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SandboxComponent} from './sandbox.component';

const routes: Routes = [{
  path: '',
  component: SandboxComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class SandboxRoutingModule {}

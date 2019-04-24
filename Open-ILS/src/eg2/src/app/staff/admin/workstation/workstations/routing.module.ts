import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {WorkstationsComponent} from './workstations.component';

// Note that we need a path value (e.g. 'manage') because without it
// there is nothing for the router to match, unless we rely on the parent
// module to handle all of our routing for us.
const routes: Routes = [
  {
    path: 'manage',
    component: WorkstationsComponent
  }, {
    path: 'remove/:remove',
    component: WorkstationsComponent
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class WorkstationsRoutingModule {
}


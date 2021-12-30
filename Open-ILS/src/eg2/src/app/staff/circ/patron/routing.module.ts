import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'bcsearch',
    loadChildren: () =>
      import('./bcsearch/bcsearch.module').then(m => m.BcSearchModule)
  },
  { path: 'event-log',
    loadChildren: () =>
      import('./event-log/event-log.module').then(m => m.EventLogModule)
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircPatronRoutingModule {}

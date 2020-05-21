import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'vandelay',
    loadChildren: () =>
      import('./vandelay/vandelay.module').then(m => m.VandelayModule)
  }, {
    path: 'authority',
    loadChildren: () =>
      import('./authority/authority.module').then(m => m.AuthorityModule)
  }, {
    path: 'marcbatch',
    loadChildren: () =>
      import('./marcbatch/marcbatch.module').then(m => m.MarcBatchModule)
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CatRoutingModule {}

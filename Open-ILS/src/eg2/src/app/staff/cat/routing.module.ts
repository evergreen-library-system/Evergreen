import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {BibByIdentComponent} from './bib-by-ident.component';

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
  }, {
    path: 'item',
    loadChildren: () => import('./item/item.module').then(m => m.ItemModule)
  }, {
    path: 'bib-from/:identType',
    component: BibByIdentComponent
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CatRoutingModule {}

import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'bcsearch',
    loadChildren: () =>
      import('./bcsearch/bcsearch.module').then(m => m.BcSearchModule)
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircPatronRoutingModule {}

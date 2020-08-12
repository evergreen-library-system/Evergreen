import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
  path: 'patron',
  loadChildren: () =>
    import('./patron/patron.module').then(m => m.PatronManagerModule)
}, {
  path: 'item',
  loadChildren: () =>
    import('./item/routing.module').then(m => m.CircItemRoutingModule)
}, {
  path: 'holds',
  loadChildren: () =>
    import('./holds/holds.module').then(m => m.HoldsUiModule)
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircRoutingModule {}

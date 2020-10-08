import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
  path: 'search',
  loadChildren: () =>
    import('./search/acq-search.module').then(m => m.AcqSearchModule)
}, {
  path: 'provider',
  loadChildren: () =>
    import('./provider/acq-provider.module').then(m => m.AcqProviderModule)
}, {
  path: 'po',
  loadChildren: () => import('./po/po.module').then(m => m.PoModule)
}, {
  path: 'picklist',
  loadChildren: () =>
    import('./picklist/picklist.module').then(m => m.PicklistModule)
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AcqRoutingModule {}

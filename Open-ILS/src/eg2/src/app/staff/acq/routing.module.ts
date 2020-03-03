import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
  { path: 'search',
    loadChildren: () =>
      import('./search/acq-search.module').then(m => m.AcqSearchModule)
  },
  { path: 'provider',
    loadChildren: () =>
      import('./provider/acq-provider.module').then(m => m.AcqProviderModule)
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class AcqRoutingModule {}

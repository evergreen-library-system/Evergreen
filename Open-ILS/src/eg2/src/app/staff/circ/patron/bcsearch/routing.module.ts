import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {BcSearchComponent} from './bcsearch.component';

const routes: Routes = [
  { path: '',
    component: BcSearchComponent
  },
  { path: ':barcode',
    component: BcSearchComponent
  },
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class BcSearchRoutingModule {}

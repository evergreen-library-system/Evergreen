import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CatalogComponent} from './catalog.component';
import {ResultsComponent} from './result/results.component';
import {RecordComponent} from './record/record.component';
import {CatalogResolver} from './resolver.service';

const routes: Routes = [{
  path: '',
  component: CatalogComponent,
  resolve: {catResolver : CatalogResolver},
  children : [{
    path: 'search',
    component: ResultsComponent
  }, {
    path: 'record/:id',
    component: RecordComponent
  }, {
    path: 'record/:id/:tab',
    component: RecordComponent
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [CatalogResolver]
})

export class CatalogRoutingModule {}

import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CatalogComponent} from './catalog.component';
import {ResultsComponent} from './result/results.component';
import {RecordComponent} from './record/record.component';
import {CatalogResolver} from './resolver.service';
import {HoldComponent} from './hold/hold.component';
import {BrowseComponent} from './browse.component';
import {CnBrowseComponent} from './cnbrowse.component';

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
    path: 'hold/:type',
    component: HoldComponent
  }, {
    path: 'record/:id/:tab',
    component: RecordComponent
  }]}, {
    // Browse is a top-level UI
    path: 'browse',
    component: BrowseComponent,
    resolve: {catResolver : CatalogResolver}
  }, {
    path: 'cnbrowse',
    component: CnBrowseComponent,
    resolve: {catResolver : CatalogResolver}
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [CatalogResolver]
})

export class CatalogRoutingModule {}

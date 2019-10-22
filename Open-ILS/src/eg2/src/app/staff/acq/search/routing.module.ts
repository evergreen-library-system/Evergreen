import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AcqSearchComponent} from './acq-search.component';
import {AttrDefsResolver} from './resolver.service';
import {AttrDefsService} from './attr-defs.service';

const routes: Routes = [
  { path: '',
    component: AcqSearchComponent,
    resolve: { attrDefsResolver : AttrDefsResolver },
    runGuardsAndResolvers: 'always'
  },
  { path: ':searchtype',
    component: AcqSearchComponent,
    resolve: { attrDefsResolver : AttrDefsResolver },
    runGuardsAndResolvers: 'always'
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [AttrDefsResolver, AttrDefsService]
})

export class AcqSearchRoutingModule {}

import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {AcqProviderComponent} from './acq-provider.component';
import {ProviderResolver, CanLeaveAcqProviderGuard} from './resolver.service';

const routes: Routes = [
  { path: '',
    component: AcqProviderComponent,
    runGuardsAndResolvers: 'always'
  },
  { path: ':id',
    component: AcqProviderComponent,
    resolve: { providerResolver : ProviderResolver },
    runGuardsAndResolvers: 'always'
  },
  { path: ':id/:tab',
    component: AcqProviderComponent,
    resolve: { providerResolver : ProviderResolver },
    canDeactivate: [CanLeaveAcqProviderGuard],
    runGuardsAndResolvers: 'always'
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: [ProviderResolver, CanLeaveAcqProviderGuard]
})

export class AcqProviderRoutingModule {}

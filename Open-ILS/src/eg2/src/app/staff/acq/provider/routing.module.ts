import {NgModule} from '@angular/core';
import {RouterModule, Routes, UrlSegment, UrlMatchResult} from '@angular/router';
import {AcqProviderComponent} from './acq-provider.component';
import {ProviderResolver, CanLeaveAcqProviderGuard} from './resolver.service';

export function providerRouteMatcher(segments: UrlSegment[]) {
    // using a custom matcher so that we
    // don't force a component re-initialization
    // when navigating from the search form to a
    // provider record
    if (segments.length === 0) {
        return {
            consumed: segments,
            posParams: {}
        };
    } else if (segments.length === 1) {
        return {
            consumed: segments,
            posParams: {
                id: segments[0],
            }
        };
    } else if (segments.length > 1) {
        return {
            consumed: segments,
            posParams: {
                id: segments[0],
                tab: segments[1],
            }
        };
    }
    return <UrlMatchResult>(null as any);
}

const routes: Routes = [
  { matcher: providerRouteMatcher,
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

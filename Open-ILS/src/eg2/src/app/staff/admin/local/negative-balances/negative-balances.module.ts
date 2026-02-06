import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {NegativeBalancesRoutingModule} from './routing.module';
import {NegativeBalancesComponent} from './list.component';

@NgModule({
    imports: [
        AdminCommonModule,
        NegativeBalancesComponent,
        NegativeBalancesRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class NegativeBalancesModule {
}



import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CopyLocOrderRoutingModule} from './copy-loc-order-routing.module';
import {CopyLocOrderComponent} from './copy-loc-order.component';

@NgModule({
    imports: [
        CopyLocOrderComponent,
        AdminCommonModule,
        CopyLocOrderRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CopyLocOrderModule {
}



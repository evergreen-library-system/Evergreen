import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CircLimitSetComponent} from './circ_limit_set.component';
import {CircLimitSetEditComponent} from './circ_limit_set_edit.component';
import {CircLimitSetRoutingModule} from './circ_limit_set_routing.module';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';

@NgModule({
    declarations: [
        CircLimitSetComponent,
        CircLimitSetEditComponent
    ],
    imports: [
        AdminCommonModule,
        AdminPageModule,
        CircLimitSetRoutingModule,
        ItemLocationSelectModule,
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CircLimitSetModule {
}

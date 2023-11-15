import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {DistributionFormulasRoutingModule} from './routing.module';
import {DistributionFormulasComponent} from './distribution-formulas.component';
import {DistributionFormulaEditDialogComponent} from './distribution-formula-edit-dialog.component';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';

@NgModule({
    declarations: [
        DistributionFormulasComponent,
        DistributionFormulaEditDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AdminCommonModule,
        ItemLocationSelectModule,
        DistributionFormulasRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class DistributionFormulasModule {
}

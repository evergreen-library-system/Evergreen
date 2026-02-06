import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {DistributionFormulasRoutingModule} from './routing.module';
import {DistributionFormulasComponent} from './distribution-formulas.component';
import {DistributionFormulaEditDialogComponent} from './distribution-formula-edit-dialog.component';
import { ItemLocationSelectComponent } from '@eg/share/item-location-select/item-location-select.component';

@NgModule({
    imports: [
        DistributionFormulasComponent,
        DistributionFormulaEditDialogComponent,
        StaffCommonModule,
        AdminCommonModule,
        ItemLocationSelectComponent,
        DistributionFormulasRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class DistributionFormulasModule {
}

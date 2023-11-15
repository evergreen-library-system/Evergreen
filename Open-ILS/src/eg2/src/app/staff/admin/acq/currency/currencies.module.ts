import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CurrenciesRoutingModule} from './routing.module';
import {CurrenciesComponent} from './currencies.component';
import {ExchangeRatesDialogComponent} from './exchange-rates-dialog.component';

@NgModule({
    declarations: [
        CurrenciesComponent,
        ExchangeRatesDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AdminCommonModule,
        CurrenciesRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CurrenciesModule {
}

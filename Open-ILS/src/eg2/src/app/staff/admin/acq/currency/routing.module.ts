import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CurrenciesComponent} from './currencies.component';

const routes: Routes = [{
    path: '',
    component: CurrenciesComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CurrenciesRoutingModule {}

import {NgModule} from '@angular/core';
import {ReactiveFormsModule} from '@angular/forms';
import {StaffCommonModule} from '@eg/staff/common.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {Z3950SearchComponent, AutofocusDirective} from './z3950-search.component';
import {Z3950SearchService} from './z3950.service';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';
import { FastAddSelectorComponent } from '../marc-edit/fast-add-selector-component';

@NgModule({
    declarations: [
        Z3950SearchComponent,
        AutofocusDirective
    ],
    imports: [
        FastAddSelectorComponent,
        MarcEditModule,
        StaffCommonModule,
        GridModule,
        ReactiveFormsModule
    ],
    exports: [
        Z3950SearchComponent,
        AutofocusDirective
    ],
    providers: [
        Z3950SearchService
    ]
})

export class Z3950SearchModule {}


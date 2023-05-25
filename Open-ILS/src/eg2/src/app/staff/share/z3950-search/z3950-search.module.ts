import {NgModule} from '@angular/core';
import {ReactiveFormsModule} from '@angular/forms';
import {StaffCommonModule} from '@eg/staff/common.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {Z3950SearchComponent, AutofocusDirective} from './z3950-search.component';
import {Z3950SearchService} from './z3950.service';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';

@NgModule({
    declarations: [
        Z3950SearchComponent,
        AutofocusDirective
    ],
    imports: [
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


import {NgModule} from '@angular/core';
import {ReactiveFormsModule} from '@angular/forms';
import {StaffCommonModule} from '@eg/staff/common.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {Z3950SearchComponent, AutofocusDirective} from './z3950-search.component';
import {Z3950SearchService} from './z3950.service';
import { FastAddSelectorComponent } from '../marc-edit/fast-add-selector.component';
import { MarcEditorDialogComponent } from '../marc-edit/editor-dialog.component';

@NgModule({
    imports: [
        FastAddSelectorComponent,
        AutofocusDirective,
        MarcEditorDialogComponent,
        StaffCommonModule,
        GridModule,
        ReactiveFormsModule,
        Z3950SearchComponent,
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


import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {GridComponent} from './grid.component';
import {GridColumnComponent} from './grid-column.component';
import {GridHeaderComponent} from './grid-header.component';
import {GridBodyComponent} from './grid-body.component';
import {GridBodyCellComponent} from './grid-body-cell.component';
import {GridToolbarComponent} from './grid-toolbar.component';
import {GridToolbarButtonComponent} from './grid-toolbar-button.component';
import {GridToolbarCheckboxComponent} from './grid-toolbar-checkbox.component';
import {GridToolbarActionComponent} from './grid-toolbar-action.component';
import {GridColumnConfigComponent} from './grid-column-config.component';
import {GridColumnWidthComponent} from './grid-column-width.component';
import {GridPrintComponent} from './grid-print.component';


@NgModule({
    declarations: [
        // public + internal components
        GridComponent,
        GridColumnComponent,
        GridHeaderComponent,
        GridBodyComponent,
        GridBodyCellComponent,
        GridToolbarComponent,
        GridToolbarButtonComponent,
        GridToolbarCheckboxComponent,
        GridToolbarActionComponent,
        GridColumnConfigComponent,
        GridColumnWidthComponent,
        GridPrintComponent
    ],
    imports: [
        EgCommonModule
    ],
    exports: [
        // public components
        GridComponent,
        GridColumnComponent,
        GridToolbarButtonComponent,
        GridToolbarCheckboxComponent,
        GridToolbarActionComponent
    ],
    providers: [
    ]
})

export class GridModule {

}

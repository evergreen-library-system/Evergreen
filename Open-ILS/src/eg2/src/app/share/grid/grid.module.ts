import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {GridComponent} from './grid.component';
import {GridColumnComponent} from './grid-column.component';
import {GridHeaderComponent} from './grid-header.component';
import {GridBodyComponent} from './grid-body.component';
import {GridBodyCellComponent} from './grid-body-cell.component';
import {GridToolbarComponent} from './grid-toolbar.component';
import {GridToolbarButtonComponent} from './grid-toolbar-button.component';
import {GridToolbarCheckboxComponent} from './grid-toolbar-checkbox.component';
import {GridToolbarActionComponent} from './grid-toolbar-action.component';
import {GridToolbarActionsMenuComponent} from './grid-toolbar-actions-menu.component';
import {GridColumnConfigComponent} from './grid-column-config.component';
import {GridColumnWidthComponent} from './grid-column-width.component';
import {GridPrintComponent} from './grid-print.component';
import {GridFilterControlComponent} from './grid-filter-control.component';


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
        GridToolbarActionsMenuComponent,
        GridColumnConfigComponent,
        GridColumnWidthComponent,
        GridPrintComponent,
        GridFilterControlComponent
    ],
    imports: [
        EgCommonModule,
        CommonWidgetsModule
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

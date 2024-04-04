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
import {GridPrintComponent} from './grid-print.component';
import {GridFilterControlComponent} from './grid-filter-control.component';
import {GridToolbarActionsEditorComponent} from './grid-toolbar-actions-editor.component';
import {GridFlatDataService} from './grid-flat-data.service';
import {GridManageFiltersDialogComponent} from './grid-manage-filters-dialog.component';


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
        GridPrintComponent,
        GridFilterControlComponent,
        GridToolbarActionsEditorComponent,
        GridManageFiltersDialogComponent
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
        GridFlatDataService
    ]
})

export class GridModule {

}

/**
 * Modules, services, and components used by all apps.
 */
import {CommonModule, DatePipe, CurrencyPipe} from '@angular/common';
import {NgModule, ModuleWithProviders} from '@angular/core';
import {RouterModule} from '@angular/router';
import {FormsModule} from '@angular/forms';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap';

/*
Note core services are injected into 'root'.
They do not have to be added to the providers list.
*/

// consider moving these to core...
import {FormatService} from '@eg/core/format.service';
import {PrintService} from '@eg/share/print/print.service';

// Globally available components
import {PrintComponent} from '@eg/share/print/print.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

@NgModule({
  declarations: [
    PrintComponent,
    DialogComponent,
    AlertDialogComponent,
    ConfirmDialogComponent,
    PromptDialogComponent,
    ProgressInlineComponent,
    ProgressDialogComponent
  ],
  imports: [
    CommonModule,
    FormsModule,
    RouterModule,
    NgbModule
  ],
  exports: [
    CommonModule,
    RouterModule,
    NgbModule,
    FormsModule,
    PrintComponent,
    DialogComponent,
    AlertDialogComponent,
    ConfirmDialogComponent,
    PromptDialogComponent,
    ProgressInlineComponent,
    ProgressDialogComponent
  ]
})

export class EgCommonModule {
    /** forRoot() lets us define services that should only be
     * instantiated once for all loaded routes */
    static forRoot(): ModuleWithProviders {
        return {
            ngModule: EgCommonModule,
            providers: [
                DatePipe,
                CurrencyPipe,
                PrintService,
                FormatService
            ]
        };
    }
}


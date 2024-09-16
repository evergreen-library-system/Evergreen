import {Component, Input, ViewChild} from '@angular/core';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';

@Component({
    selector: 'eg-bucket-action-summary-dialog',
    template: `
  <eg-alert-dialog #actionSummaryDialog
    dialogTitle="{{dialogTitle}}"
    [dialogBodyTemplate]="actionResults">
  </eg-alert-dialog>
  <ng-template #actionResults>
    <div div="row" *ngFor="let container of containers">
      <div class="col" i18n>Bucket #{{container.id}}</div>
      <div class="col">{{containerActionResultMap[container.id]}}</div>
    </div>
  </ng-template>
  `
})

export class BucketActionSummaryDialogComponent {

    @Input() dialogTitle: string = $localize`Bucket Action Summary`;
    containers: any[];
    containerActionResultMap: any;

    @ViewChild('actionSummaryDialog', { static: true })
    private actionSummaryDialog: AlertDialogComponent;

    constructor() {}

    open(containers: any[], containerActionResultMap: any) {
        this.containers = containers;
        this.containerActionResultMap = containerActionResultMap;
        return this.actionSummaryDialog.open();
    }
}


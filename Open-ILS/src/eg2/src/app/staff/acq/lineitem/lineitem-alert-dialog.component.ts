import {Component, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    selector: 'eg-lineitem-alert-dialog',
    templateUrl: './lineitem-alert-dialog.component.html'
})

export class LineitemAlertDialogComponent {
    @Input() liId: number;
    @Input() title: string;
    @Input() alertText: IdlObject;
    @Input() alertComment: string;
    @Input() numAlerts = 0;
    @Input() alertIndex = 0;

    @ViewChild('confirmAlertsDialog') confirmAlertsDialog: ConfirmDialogComponent;

    open(): Observable<any> {
        return this.confirmAlertsDialog.open();
    }
}

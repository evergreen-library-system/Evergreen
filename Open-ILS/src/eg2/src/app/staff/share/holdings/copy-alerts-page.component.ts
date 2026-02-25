import { Component, AfterViewInit, ViewChild, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { CopyAlertsDialogComponent } from './copy-alerts-dialog.component';
import { StaffBannerComponent } from '../staff-banner.component';

@Component({
    selector: 'eg-copy-alerts-page',
    templateUrl: 'copy-alerts-page.component.html',
    imports: [StaffBannerComponent, CopyAlertsDialogComponent]
})
export class CopyAlertsPageComponent implements AfterViewInit {
    private route = inject(ActivatedRoute);

    @ViewChild('copyAlertsDialog', {static: false})
    private copyAlertsDialog: CopyAlertsDialogComponent;

    copyIds = [];

    ngAfterViewInit() {
        console.debug('CopyAlertsPageComponent, ngAfterViewInit, this', this);
        this.route.queryParams.subscribe(params => {
            console.debug('CopyAlertsPageComponent, query params', params);
            if (params['copyIds']) {
                this.copyIds = params['copyIds'].split(',').map(id => parseInt(id, 10));
                this.openItemAlerts();
            }
        });
    }

    openItemAlerts($event?) {
        this.copyAlertsDialog.copyIds = this.copyIds;
        // this.copyAlertsDialog.mode = 'manage';
        this.copyAlertsDialog.open({size: 'lg'}).subscribe({
            'next': changes => {
                console.debug('CopyAlertsPageComponent, copyAlertsDialog, open, next', changes);
            },
            'error': err => {
                console.error('CopyAlertsPageComponent, copyAlertsDialog, open, error', err);
            },
            'complete': () => {
                console.debug('CopyAlertsPageComponent, copyAlertsDialog, open, complete');
                window.close();
            }
        });
    }
}

import { Component, AfterViewInit, ViewChild, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { StaffBannerComponent } from '../staff-banner.component';
import { CopyNotesDialogComponent } from './copy-notes-dialog.component';
import { BroadcastService } from '@eg/share/util/broadcast.service';

@Component({
    selector: 'eg-copy-notes-page',
    templateUrl: 'copy-notes-page.component.html',
    imports: [StaffBannerComponent, CopyNotesDialogComponent]
})
export class CopyNotesPageComponent implements AfterViewInit {
    private route = inject(ActivatedRoute);
    private broadcaster = inject(BroadcastService);

    @ViewChild('copyNotesDialog', { static: false })
    private copyNotesDialog: CopyNotesDialogComponent;

    copyIds = [];

    ngAfterViewInit() {
        this.route.queryParams.subscribe(params => {
            if (params['copyIds']) {
                this.copyIds = params['copyIds'].split(',').map(id => parseInt(id, 10));
                this.openNotes();
            }
        });
    }

    openNotes() {
        this.copyNotesDialog.copyIds = this.copyIds;
        this.copyNotesDialog.open({ size: 'lg' }).subscribe({
            next: _ => {
                // AngularJS Item Status listens for this to refresh its rows
                this.broadcaster.broadcast('eg.holdings.update', {
                    copies: this.copyIds, volumes: [], records: []
                });
            },
            error: err => {
                console.error('CopyNotesPageComponent, copyNotesDialog, open, error', err);
            },
            complete: () => window.close()
        });
    }
}

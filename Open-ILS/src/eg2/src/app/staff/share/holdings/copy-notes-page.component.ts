import { Component, AfterViewInit, ViewChild, inject } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { StaffBannerComponent } from '../staff-banner.component';
import { CopyNotesDialogComponent } from './copy-notes-dialog.component';
import { BroadcastService } from '@eg/share/util/broadcast.service';
import { LinkTargetService } from '@eg/share/link-target/link-target.service';
import { take } from 'rxjs';

@Component({
    selector: 'eg-copy-notes-page',
    templateUrl: 'copy-notes-page.component.html',
    imports: [StaffBannerComponent, CopyNotesDialogComponent]
})
export class CopyNotesPageComponent implements AfterViewInit {
    private route = inject(ActivatedRoute);
    private router = inject(Router);
    private broacaster = inject(BroadcastService);
    private linkTarget = inject(LinkTargetService);

    @ViewChild('copyNotesDialog', { static: false })
    private copyNotesDialog: CopyNotesDialogComponent;

    copyIds = [];
    private newTabsDisabled = false;
    private recordId = '';

    ngAfterViewInit() {
        this.linkTarget.newTabsDisabled$.pipe(
            take(1)
        ).subscribe(disabled => {
            this.newTabsDisabled = !!disabled;
        });

        this.route.queryParams.subscribe(params => {
            if (params['recordId']) {
                this.recordId = params['recordId'];
            }
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
                this.broacaster.broadcast('eg.holdings.update', {
                    copies: this.copyIds, volumes: [], records: []
                });
            },
            error: err => {
                console.error('CopyNotesPageComponent, copyNotesDialog, open, error', err);
            },
            complete: () => {
                // If new tab links are disabled and we did not open the
                // tab via JavaScript, assume we should not close it and
                // instead redirect to the catalog record.
                if (this.newTabsDisabled && !window.opener && this.recordId) {
                    const id = this.recordId.replace(/\D/g, '');
                    this.router.navigate([`/staff/catalog/record/${id}`]);
                } else {
                    window.close();
                }
            }
        });
    }
}

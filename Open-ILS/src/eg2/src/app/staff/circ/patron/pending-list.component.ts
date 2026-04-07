import { Component, inject, ViewChild } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { GridDataSource } from '@eg/share/grid/grid';
import { PendingListService, PendingPatron } from './pending-list.service';
import { GridComponent } from '@eg/share/grid/grid.component';
import { ConfirmDialogComponent } from '@eg/share/dialog/confirm.component';
import { filter, switchMap } from 'rxjs';
import { BroadcastService } from '@eg/share/util/broadcast.service';

@Component({
    selector: 'eg-pending-patrons',
    templateUrl: './pending-list.component.html'
})
export class PendingListComponent {

    private readonly broadcast = inject(BroadcastService);
    private readonly pending = inject(PendingListService);

    contextOrg = this.pending.defaultContextOrg();
    dataSource = new GridDataSource();

    @ViewChild('grid', { static: true }) grid!: GridComponent;
    @ViewChild('confirmDelete',
        { static: true }
    ) confirmDeleteDialog!: ConfirmDialogComponent;

    constructor() {
        this.dataSource.getRows = (pager, _) =>
            this.pending.getPendingPatrons(this.contextOrg, pager);

        // If a staged patron is registered, reload the grid
        this.broadcast.listen('eg.pending_usr.update').subscribe(
            event => {
                if (event?.usr?.home_ou === this.contextOrg) {
                    this.grid.reload();
                }
            }
        );
    }

    deletePendingPatrons(patrons: PendingPatron[]): void {
        this.confirmDeleteDialog.open().pipe(
            filter(confirmed => confirmed),
            switchMap(() => this.pending.deletePendingPatrons(patrons))
        ).subscribe(() => this.grid.reload());
    }

    loadPendingPatron([patron]: PendingPatron[]): void {
        if (!patron) { return; }
        this.pending.loadPendingPatron(patron);
    }

    pendingOrgChanged(org: IdlObject | null): void {
        if (!org) { return; }
        this.contextOrg = org.id();
        this.grid.reload();
    }

}

import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ConjoinedItemsDialogComponent
} from '@eg/staff/share/holdings/conjoined-items-dialog.component';

/** Conjoined items per record grid */

@Component({
    selector: 'eg-catalog-record-conjoined',
    templateUrl: 'conjoined.component.html'
})
export class ConjoinedComponent implements OnInit {

    @Input() recordId: number;

    hasPerm: boolean;
    gridDataSource: GridDataSource;
    idsToUnlink: number[];

    @ViewChild('conjoinedGrid', { static: true }) private grid: GridComponent;

    @ViewChild('conjoinedDialog', { static: true })
    private conjoinedDialog: ConjoinedItemsDialogComponent;

    @ViewChild('confirmUnlink', { static: true })
    private confirmUnlink: ConfirmDialogComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private perm: PermService
    ) {
        this.gridDataSource = new GridDataSource();
        this.idsToUnlink = [];
    }

    ngOnInit() {
        // Load edit perms
        this.perm.hasWorkPermHere(['UPDATE_COPY'])
            .then(perms => this.hasPerm = perms.UPDATE_COPY);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) { // Sort provided by grid.
                orderBy.bmp = sort[0].name + ' ' + sort[0].dir;
            } else {
                orderBy.bmp = 'id';
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('bpbcm',
                {peer_record: this.recordId}, searchOps, {fleshSelectors: true});
        };
    }

    async unlink(rows: any) {

        this.idsToUnlink = rows.map(r => r.target_copy().id());
        if (this.idsToUnlink.length === 0) { return; }

        this.confirmUnlink.open({size: 'sm'}).subscribe(confirmed => {

            if (!confirmed) { return; }

            const maps = [];
            this.pcrud.search('bpbcm',
                {target_copy: this.idsToUnlink, peer_record: this.recordId})
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                .subscribe(
                    { next: map => maps.push(map), error: (err: unknown) => {}, complete: () => {
                        // eslint-disable-next-line rxjs-x/no-nested-subscribe
                        this.pcrud.remove(maps).subscribe(
                            { next: ok => console.debug('deleted map ', ok), error: (err: unknown) => console.error(err), complete: ()  => {
                                this.idsToUnlink = [];
                                this.grid.reload();
                            } }
                        );
                    } }
                );
        });
    }

    openConjoinedDialog() {
        this.conjoinedDialog.open({size: 'sm'}).subscribe(
            modified => {
                if (modified) {
                    this.grid.reload();
                }
            }
        );
    }
}


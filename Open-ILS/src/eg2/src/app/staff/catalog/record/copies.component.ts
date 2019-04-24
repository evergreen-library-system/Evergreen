import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {StaffCatalogService} from '../catalog.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';

@Component({
  selector: 'eg-catalog-copies',
  templateUrl: 'copies.component.html'
})
export class CopiesComponent implements OnInit {

    recId: number;
    initDone = false;
    gridDataSource: GridDataSource;
    copyContext: any; // grid context
    @ViewChild('copyGrid') copyGrid: GridComponent;

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.copyGrid.reload();
        }
    }

    constructor(
        private net: NetService,
        private org: OrgService,
        private staffCat: StaffCatalogService,
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.initDone = true;

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            // sorting not currently supported
            return this.fetchCopies(pager);
        };

        this.copyContext = {
            holdable: (copy: any) => {
                return copy.holdable === 't'
                    && copy.location_holdable === 't'
                    && copy.status_holdable === 't';
            }
        };
    }

    collectData() {
        if (!this.recId) { return; }
    }

    orgName(orgId: number): string {
        return this.org.get(orgId).shortname();
    }

    fetchCopies(pager: Pager): Observable<any> {
        if (!this.recId) { return of([]); }

        // "Show Result from All Libraries" i.e. global search displays
        // copies from all branches, sorted by search/pref libs.
        const copy_depth = this.staffCat.searchContext.global ?
            this.org.root().ou_type().depth() :
            this.staffCat.searchContext.searchOrg.ou_type().depth();

        return this.net.request(
            'open-ils.search',
            'open-ils.search.bib.copies.staff',
            this.recId,
            this.staffCat.searchContext.searchOrg.id(),
            copy_depth,
            pager.limit,
            pager.offset,
            this.staffCat.prefOrg ? this.staffCat.prefOrg.id() : null
        ).pipe(map(copy => {
            copy.active_date = copy.active_date || copy.create_date;
            return copy;
        }));
    }
}



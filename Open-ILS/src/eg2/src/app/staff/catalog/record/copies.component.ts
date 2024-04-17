import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {StaffCatalogService} from '../catalog.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {CourseService} from '@eg/staff/share/course.service';
import {PermService} from '@eg/core/perm.service';

@Component({
  selector: 'eg-catalog-copies',
  templateUrl: 'copies.component.html'
})
export class CopiesComponent implements OnInit {

    recId: number;
    initDone = false;
    usingCourseModule = false;
    editableCopyLibs: number[] = [];
    editableCNLibs: number[] = [];
    gridDataSource: GridDataSource;
    copyContext: any; // grid context
    @ViewChild('copyGrid', { static: true }) copyGrid: GridComponent;

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.copyGrid.reload();
        }
    }

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private course: CourseService,
        private net: NetService,
        private org: OrgService,
        private staffCat: StaffCatalogService,
        private broadcaster: BroadcastService,
        private perm: PermService
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.initDone = true;
        this.course.isOptedIn().then(res => {
            this.usingCourseModule = res;
        });

        this.perm.hasWorkPermAt(['UPDATE_COPY','UPDATE_VOLUME'], true)
            .then(result => {
                this.editableCopyLibs = result.UPDATE_COPY as number[];
                this.editableCNLibs = result.UPDATE_VOLUME as number[];
        });

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            // sorting not currently supported
            return this.fetchCopies(pager);
        };

        this.copyContext = {
            editable: (copy: any) => {
                return this.editableCopyLibs.some(lib => {
                    return copy.circ_lib === lib
                        || copy.call_number_owning_lib === lib;
                });
            },
            editableCN: (copy: any) => {
                return this.editableCNLibs.some(lib => {
                    return copy.call_number_owning_lib === lib;
                });
            },
            holdable: (copy: any) => {
                return copy.holdable === 't'
                    && copy.location_holdable === 't'
                    && copy.status_holdable === 't';
            }
        };

        this.cellTextGenerator = {
            callnumber: row => (`${row.call_number_prefix_label} ` +
                `${row.call_number_label} ${row.call_number_suffix_label}`).trim(),
            holdable: row => this.copyContext.holdable(row),
            barcode: row => row.barcode
        };

        this.broadcaster.listen('eg.holdings.update').subscribe(data => {
            if (data && data.records && data.records.includes(this.recId)) {
                this.copyGrid.reload();
            }
        });
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
            this.org.settings('circ.course_materials_opt_in').then(res => {
                if (res['circ.course_materials_opt_in']) {
                    this.course.getCoursesFromMaterial(copy.id).then(courseList => {
                        copy._courses = courseList;
                    });
                }
            });
            copy.active_date = copy.active_date || copy.create_date;
            return copy;
        }));
    }
}



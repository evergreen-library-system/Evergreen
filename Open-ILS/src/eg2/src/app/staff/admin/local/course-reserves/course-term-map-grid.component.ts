import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Observable, map, switchMap} from 'rxjs';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';

@Component({
    selector: 'eg-course-term-map-grid',
    templateUrl: './course-term-map-grid.component.html',
})
export class CourseTermMapGridComponent implements OnInit {
    @Input() courseId: number;
    @ViewChild('grid') private grid: GridComponent;
    @ViewChild('editDialog') private editDialog: FmRecordEditorComponent;

    readonlyFields: string;

    defaultNewAcmtcm: IdlObject;
    gridDataSource: GridDataSource;
    createNew: () => void;
    deleteSelected: (rows: IdlObject[]) => void;
    termEntryGenerator: (course: number) => (query: string) => Observable<ComboboxEntry>;
    termEntries: (query: string) => Observable<ComboboxEntry>;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
    ) {
        this.gridDataSource = new GridDataSource();
        this.defaultNewAcmtcm = this.idl.create('acmtcm');
    }

    ngOnInit() {

        if (this.courseId) {
            this.defaultNewAcmtcm.course(this.courseId);
            this.readonlyFields = 'course';
        }

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            const criteria = this.courseId ? {course: this.courseId} : {};

            return this.pcrud.search('acmtcm',
                criteria, searchOps, {fleshSelectors: true});
        };

        // Produce a bespoke callback for the combobox search, which
        // limits the results to course terms that make sense for the
        // selected course.  This prevents users from associating a
        // course at their library to a term from a completely different
        // academic calendar.
        this.termEntryGenerator = (courseId: number) => {
            return (query: string) => {
                return this.pcrud.retrieve('acmc', courseId).pipe(switchMap(fullCourseObject => {
                    return this.pcrud.search(
                        'acmt', {
                            name: {'ilike': `%${query}`},
                            owning_lib: this.org.ancestors(fullCourseObject.owning_lib(), true)
                        },
                        {order_by: {'acmt': 'name'}}
                    );
                }), map(courseTerm => {
                    return {id: courseTerm.id(), label: courseTerm.name()};
                }));
            };
        };

        this.createNew = () => {
            this.editDialog.mode = 'create';
            this.editDialog.open({size: 'lg'})
                .subscribe(() => this.grid.reload());
        };

        this.deleteSelected = (termMaps: IdlObject[]) => {
            termMaps.forEach(termMap => termMap.isdeleted(true));
            this.pcrud.autoApply(termMaps).subscribe(
                { next: val => console.debug('deleted: ' + val), error: (err: unknown) => {}, complete: ()  => this.grid.reload() }
            );
        };
    }
}

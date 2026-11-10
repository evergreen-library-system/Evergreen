import { Component, EventEmitter, inject, Input, Output, ViewChild, OnInit } from '@angular/core';
import { GridDataSource } from '@eg/share/grid/grid';
import { Pager } from '@eg/share/util/pager';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { GridComponent } from '@eg/share/grid/grid.component';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { mergeMap, Observable, tap, of, switchMap, catchError } from 'rxjs';
import { FmRecordEditorModule } from '@eg/share/fm-editor/fm-editor.module';
import { GridFlatDataService } from '@eg/share/grid/grid-flat-data.service';
import { HoldGroupsService } from '../hold-groups.service';
import { ConfirmDialogComponent } from '@eg/share/dialog/confirm.component';
import { NetService } from '@eg/core/net.service';

export interface tabChange {
  tab: 'list' | 'users' | 'events';
  id?: number;
}
@Component({
    selector: 'eg-hold-group-list',
    standalone: true,
    imports: [StaffCommonModule, FmRecordEditorModule],
    templateUrl: './hold-group-list.component.html'
})
export class HoldGroupListComponent implements OnInit {
    private auth = inject(AuthService);
    private pcrud = inject(PcrudService);
    private idl = inject(IdlService);
    private flatData = inject(GridFlatDataService);
    private hg = inject(HoldGroupsService);
    private net = inject(NetService);

    holdGroupsDataSource: GridDataSource = new GridDataSource();
  @ViewChild('grid', {static: true}) grid!: GridComponent;
  @ViewChild('editDialog', { static: true }) editDialog!: FmRecordEditorComponent;
  @ViewChild('deleteDialog', { static: true }) deleteDialog!: ConfirmDialogComponent;

  defaultUserBucket!: IdlObject;
  bucketToDeleteName!: string;

  @Input() selectedUserBucket: IdlObject | null = null;
  @Output() selectedUserBucketChange = new EventEmitter<number | null>();
  @Output() tabAndBucketChange = new EventEmitter<tabChange>();

  ngOnInit(): void {
      const rec = this.idl.create('cub');
      rec.btype('hold_subscription');
      rec.owner(this.auth.user().id());
      rec.owning_lib(this.auth.user().ws_ou());
      rec.pub(false);

      this.defaultUserBucket = rec;

      this.holdGroupsDataSource.getRows = (pager: Pager, sort: any[]) => {

          // const query = this.flatData.addFiltersToQuery(this.grid.context, {btype: 'hold_subscription'});

          // return this.flatData.getRows(this.grid.context, query, pager, sort);

          const order_by: any = {};
          if (sort.length) {
          // Sort specified from grid
              order_by['cub'] = sort[0].name + ' ' + sort[0].dir;
          }

          const pcrudOps = {
              offset: pager.offset,
              limit: pager.limit,
              order_by: order_by,
              flesh_fields: {cub: ['items']},
              flesh: 1
          };

          const reqOps = {
              fleshSelectors: true
          };
          const query = this.flatData.addFiltersToQuery(this.grid.context, { btype: 'hold_subscription'});

          return this.pcrud.search('cub', query, pcrudOps, reqOps).pipe(
              mergeMap((response) => this.addNumUsersInEachBucket(response))
          );
      };
  }

  addNumUsersInEachBucket(row: IdlObject): Observable<IdlObject> {
      row['num_users'] = row.items().length;
      return of(row);
  }

  has_none_selected(): boolean {
      return this.grid.context.getSelectedRows?.()?.length === 0;
  }

  createHoldGroup() {
      this.editDialog.mode = 'create';
      this.editDialog.open().subscribe(() => {
          this.grid.reload();
      });
  }

  editHoldGroup() {
      this.editDialog.record = this.grid.context.getSelectedRows()?.[0];
      this.editDialog.mode = 'update';
      // this.editDialog.inPlaceMode = true;
      this.editDialog.open({}).subscribe({
          next: (val) => {
              this.grid.reload();
          },
          error: (err) => {
              console.log('Error occurred while editing hold group: ', err);
          }
      });
  }

  deleteHoldGroup() {
      const selectedRow = this.grid.context.getSelectedRows()?.[0];
      this.bucketToDeleteName = selectedRow.name();
      this.deleteDialog.open().pipe(
          switchMap((res) => {
              if (!res) {
                  return of(null);
              }

              return this.net.request(
                  'open-ils.actor',
                  'open-ils.actor.container.full_delete',
                  this.auth.token(),
                  'user',
                  selectedRow.id()
              );
          }),
          catchError((err) => {
              console.error('Error occurred while deleting hold group: ', err);
              return of(null);
          }),
          tap((res) => {
              if (res) {
                  this.grid.reload();
                  if (this.hg.userBucket && this.hg.userBucketId() === selectedRow.id()) {
                      this.hg.userBucket.set(null);
                  }
              }
          })
      ).subscribe();
  }

  selectCurrentHoldGroup() {
      this.selectHoldGroup(this.grid.context.getSelectedRows()?.[0]);
  }

  selectHoldGroup(bucket: IdlObject) {
      this.tabAndBucketChange.emit({tab: 'users', id: bucket.id()});
  }

  showHoldGroupEvents() {
      this.tabAndBucketChange.emit({tab: 'events', id: this.grid.context.getSelectedRows()?.[0].id()});
  }

}

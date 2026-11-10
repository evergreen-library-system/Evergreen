import { Component, inject, OnInit, ViewChild, effect } from '@angular/core';
import { HoldGroupInfoComponent } from '../hold-group-info/hold-group-info.component';
import { IdlObject } from '@eg/core/idl.service';
import { HoldGroupsService } from '../hold-groups.service';
import { forkJoin, mergeMap, Observable, of, switchMap, tap, throwError, map } from 'rxjs';
import { GridComponent } from '@eg/share/grid/grid.component';
import { Pager } from '@eg/share/util/pager';
import { GridModule} from '@eg/share/grid/grid.module';
import { GridColumnSort, GridDataSource } from '@eg/share/grid/grid';
import { PcrudService } from '@eg/core/pcrud.service';
import { GridFlatDataService } from '@eg/share/grid/grid-flat-data.service';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { EventService } from '@eg/core/event.service';
import { HoldTypeNamePipe } from '@eg/staff/share/holds/hold-type-name.pipe';
import { HoldGroupEventMappingInfoDialogComponent } from './hold-group-event-mapping-info-dialog.component';
import { ProgressDialogComponent } from '@eg/share/dialog/progress.component';
import { ConfirmDialogComponent } from '@eg/share/dialog/confirm.component';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-hold-group-events',
    standalone: true,
    imports: [
        HoldGroupInfoComponent,
        GridModule,
        HoldTypeNamePipe,
        HoldGroupEventMappingInfoDialogComponent,
        ProgressDialogComponent,
        ConfirmDialogComponent,
        FormsModule
    ],
    templateUrl: './hold-group-events.component.html'
})
export class HoldGroupEventsComponent implements OnInit {
    protected hg = inject(HoldGroupsService);
    private pcrud = inject(PcrudService);
    private flat = inject(GridFlatDataService);
    private net = inject(NetService);
    private auth = inject(AuthService);
    private evt = inject(EventService);

  @ViewChild('grid', {static: true}) grid!: GridComponent;
  dataSource: GridDataSource = new GridDataSource();

  @ViewChild('createDialog', {static: true}) createDialog!: ConfirmDialogComponent;
  @ViewChild('abhemInfoDialog', {static: true}) abhemInfoDialog!: HoldGroupEventMappingInfoDialogComponent;
  abhemMappings: IdlObject[] = [];
  @ViewChild('creationProgressDialog', {static: true}) creationProgressDialog!: ProgressDialogComponent;

  failEvent: any;
  runResults: any[] = [];
  runSuccessCount = 0;
  runFailCount = 0;

  targetRecordText = '';
  overrideBlocks = true;


  constructor() {
      effect(() => {
          this.hg.userBucket();
          this.grid.reload();
      });
  }

  ngOnInit(): void {
      this.dataSource.getRows = (pager: Pager, sort: GridColumnSort[]): Observable<any> => {
          const query = {
              bucket: this.hg.userBucketId()
          };
          const pcrudOps = {
              flesh: 1,
              flesh_fields: {'abhe': ['target', 'staff', 'mappings']}
          };
          const reqOps = {

          };
          return this.pcrud.search('abhe', this.flat.addFiltersToQuery(this.grid.context, query), pcrudOps, reqOps).pipe(
              // Gotta sneak information about the target bib onto this
              mergeMap((abhe) => {
                  return forkJoin([of(abhe), this.pcrud.retrieve('mwde', abhe.target())]);
              }),
              map(([abhe, mwde], index) => {
                  // Perhaps inelegant, but nyeh you're not my dad.
                  abhe.mwde = mwde;
                  abhe.title = JSON.parse(mwde.title());
                  abhe.num_placed = abhe?.mappings()?.length;
                  return abhe;
              })
          );
      };
  }

  createHoldGroupEvent() {
      this.runResults = [];
      this.runFailCount = 0;
      this.runSuccessCount = 0;
      this.failEvent = null;
      let shouldReload = false;
      this.createDialog.open({}).pipe(
          // Doing this before any results come in, so the user knows we're working on it
          tap(() => this.creationProgressDialog.open({})),
          switchMap((proceed: boolean) => {
              if (!proceed) {
                  return of(null);
              }

              if (!this.hg.userBucketId()) {
                  return throwError(() => new Error('Missing current hold group'));
              }
              const method: string = this.overrideBlocks ?
                  'open-ils.circ.holds.test_and_create.subscription_batch.override' :
                  'open-ils.circ.holds.test_and_create.subscription_batch';
              return this.net.request(
                  'open-ils.circ',
                  method,
                  this.auth.token(),
                  {pickup_lib: this.auth.user().ws_ou()},
                  this.hg.userBucketId(),
                  Number(parseInt(this.targetRecordText, 10))
              );
          }),
          map((res, index) => ({res, index})),
          tap(({res, index}) => {
              // The first emission is either an error, or the number of holds we're attempting to make
              if (index === 0) {
                  if (!res) {
                      this.creationProgressDialog.close();
                      return;
                  }
                  if (res?.ilsEvent) {
                      this.failEvent = this.evt.parse(res);
                      this.creationProgressDialog.close();
                      return;
                  }
                  if (res?.error) {
                      this.failEvent = res.error;
                      this.creationProgressDialog.close();
                      return;
                  }
                  this.creationProgressDialog.max = res.total;
                  this.creationProgressDialog.value = res.count;
              } else { // All emsssions after that are the result of attempting to make each hold
                  this.runResults.push(res);
                  this.creationProgressDialog.value = res.count;
                  this.runSuccessCount = this.runResults.filter(r => r.patronid).length;
                  this.runFailCount = this.runResults.filter(r => r.failedpatronid).length;
                  shouldReload = true;
              }
          })
      ).subscribe({
          complete: () => {
              this.targetRecordText = '';
              if (shouldReload) {
                  this.grid.reload();
              }

          }
      });
  }


  openMappingsInfoDialog(row: IdlObject) {
      this.abhemInfoDialog.mappings = row.mappings();
      this.abhemInfoDialog.eventId = row.id();
      this.abhemInfoDialog.open({size: 'xl'});
  }

  nothingSelected(): boolean {
      return !this.grid?.context?.getSelectedRows()?.length ||
        this.grid?.context?.getSelectedRows()?.length < 1;
  }

  cancelHoldGroupEvent(evt: IdlObject) {
      this.net.request(
          'open-ils.circ',
          'open-ils.circ.holds.rollback.subscription_batch',
          this.auth.token(),
          evt.id()
      ).pipe(
          // Something something progress dialog
          tap(() => this.grid.reload())
      ).subscribe();
  }

  findBucketUser(userId: number) {
      return this.hg.userBucket()?.items().find((item: IdlObject) => item.target_user().id() === userId).target_user();
  }


}

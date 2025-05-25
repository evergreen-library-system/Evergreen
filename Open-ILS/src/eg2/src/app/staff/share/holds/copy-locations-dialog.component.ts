/* eslint-disable brace-style, no-shadow */
import {Component, Input, OnDestroy, ViewChild} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {BehaviorSubject, Observable, Subject, of, catchError, exhaustMap,
    finalize, map, switchMap, tap, toArray} from 'rxjs';
/**
 * Holds pull list shelving locations filter dialog:
 * select shelving locations or shelving location groups,
 * emit applied IDL class, combobox entries, and location IDs.
 *
 * <eg-hold-copy-locations-dialog #copyLocationsDialog
 *  [contextOrg]="pullListOrg"
 *  [selectedClass]="copyLocationClass"
 *  [selectedEntries]="copyLocationEntries">
 * </eg-hold-copy-locations-dialog>
 */
@Component({
    selector: 'eg-hold-copy-locations-dialog',
    templateUrl: './copy-locations-dialog.component.html'
})
export class HoldCopyLocationsDialogComponent
    extends DialogComponent implements OnDestroy {


  // limit to locations or groups owned by this org or its ancestors
  @Input() contextOrg!: number;


  // toggle between locations and groups
  @Input() selectedClass = 'acpl';
  private pendingClass = new BehaviorSubject<string>('acpl');
  pendingClass$ = this.pendingClass.asObservable();


  // location or group entries to select from
  private entriesCache: {[orgAndClass: string]: ComboboxEntry[]} = {};
  entries$ = this.pendingClass$.pipe(
      switchMap(pendingClass => this.getEntries(pendingClass))
  );
  entriesLoading = false;


  // selected location or group entries
  @Input() selectedEntries: ComboboxEntry[] = [];
  pendingEntries: ComboboxEntry[] = [];


  // aria-live announcements
  @ViewChild('entryRemoved') private entryRemoved: StringComponent;
  @ViewChild('entriesRemoved') private entriesRemoved: StringComponent;
  announcement = '';


  // emit applied class, entries, and location IDs on dialog close
  private mappedIdsCache: {[groupId: number]: number[]} = {};
  apply = new Subject<boolean>();
  onApply = this.apply.pipe(
      exhaustMap(() => this.getMappedLocationIds())
  ).subscribe(ids =>
      this.close([this.getPendingClass(), this.pendingEntries, ids])
  );


  constructor(
    private modal: NgbModal,
    private org: OrgService,
    private pcrud: PcrudService
  ) {
      super(modal);
  }

  ngOnDestroy(): void {
      this.onApply.unsubscribe();
  }


  announce(announcement: string): void {
      this.announcement = announcement;
  }

  getPendingClass(): string {
      return this.pendingClass.getValue();
  }

  init(fmClass?: string, entries?: ComboboxEntry[]): void {
      this.pendingClass.next(fmClass ?? this.selectedClass);
      this.pendingEntries = entries ?? this.selectedEntries;
  }

  pendingEntryIds(): number[] {
      return this.pendingEntries.map(({id}) => +id);
  }

  readyToApply(): boolean {
      if (this.pendingEntries.length !== this.selectedEntries.length) {
          return true;
      }

      if (!this.pendingEntries.length) {
          return false;
      }

      if (this.getPendingClass() !== this.selectedClass) {
          return true;
      }

      const pending = new Set(this.pendingEntryIds());
      const selected = new Set(this.selectedEntries.map(({id}) => +id));
      for (const id of pending) {
          if (!selected.has(id)) {
              return true;
          }
      }

      return false;
  }

  remove({id: idToRemove, label}: ComboboxEntry): void {
      this.pendingEntries = this.pendingEntries.filter(
          ({id}) => id !== idToRemove
      );
      this.announce(`${label} ${this.entryRemoved.text}`);
  }

  removeAll(): void {
      if (this.pendingEntries.length) {
          this.init('acpl', []);
          this.announce(this.entriesRemoved.text);
      }
  }

  select(combobox: ComboboxComponent, entry: ComboboxEntry): void {
      // clear combobox after selection
      setTimeout(() => combobox.selectedId = null);

      if (entry && !this.pendingEntries.find(({id}) => id === entry.id)) {
          this.pendingEntries = this.pendingEntries.concat(entry);
      }
  }

  updatePendingClass(idlClass: string): void {
      // clear selections (don't mix locations and groups)
      this.init(idlClass, []);
  }


  // get location or group entries to select from
  private getEntries(fmClass: string): Observable<ComboboxEntry[]> {
      // check cache first
      const cacheKey = this.contextOrg + fmClass;
      if (cacheKey in this.entriesCache) {
          return of(this.entriesCache[cacheKey]);
      }

      // otherwise, prepare the pcrud search
      let ownerKey: 'owning_lib' | 'owner' = 'owning_lib';
      const search: {[key: string]: any} = {};
      const pcrudOps = {order_by: {[fmClass]: 'name'}};

      // if locations, don't include deleted locations
      if (fmClass === 'acpl') {search.deleted = 'f';}
      // if groups, use the appropriate owner key
      else {ownerKey = 'owner';}
      search[ownerKey] = this.org.ancestors(this.contextOrg, true);

      this.entriesLoading = true;
      return this.pcrud.search(fmClass, search, pcrudOps).pipe(
      // gather emissions into an array
          toArray<IdlObject>(),

          // map IDL objects into combobox entries
          map(idlObjs => idlObjs.map(idlObj => ({
              id: idlObj.id(),
              label: idlObj.name() +
          ' (' + this.org.get(idlObj[ownerKey]()).shortname() + ')'
          }))),

          // cache entries
          tap(entries => this.entriesCache[cacheKey] = entries),

          // keep stream alive on error
          catchError((error: unknown) => (console.error(error), of([]))),

          finalize(() => this.entriesLoading = false)
      );
  }


  // get location IDs or, if groups, their mapped location IDs
  private getMappedLocationIds(): Observable<number[]> {
      // if locations or an empty array of groups, return entry IDs
      const fmClass = this.getPendingClass();
      if (fmClass === 'acpl' || !this.pendingEntries.length) {
          return of([...new Set(this.pendingEntryIds())]);
      }

      // try cache
      const groupsToMap: number[] = [];
      const cachedIds = this.pendingEntries.reduce((mappedIds, {id}) => {
          if (id in this.mappedIdsCache) {
              mappedIds = mappedIds.concat(this.mappedIdsCache[id]);
          } else {
              groupsToMap.push(+id);
          }
          return mappedIds;
      }, []);

      if (!groupsToMap.length) {return of([...new Set(cachedIds)]);}

      // otherwise, prepare the pcrud search
      groupsToMap.forEach(id => this.mappedIdsCache[id] = []);
      const search = {lgroup: groupsToMap};
      const pcrudOps = {flesh: 1, flesh_fields: {acplgm: ['location']}};

      return this.pcrud.search('acplgm', search, pcrudOps).pipe(
      // gather emissions into an array
          toArray<IdlObject>(),

          // cache mapped location IDs
          tap(maps => maps.forEach(map => {
              this.mappedIdsCache[map.lgroup()].push(+map.location().id());
          })),

          // map location group maps to location IDs
          map(maps => maps.map(map => +map.location().id())),

          // include any previously cached IDs and de-duplicate
          map(ids => [...new Set(ids.concat(cachedIds))]),

          // keep stream alive on error
          catchError((error: unknown) => (console.error(error), of([])))
      );
  }

}

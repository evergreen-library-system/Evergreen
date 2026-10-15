import { Component, Input, ViewChild } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { AlertDialogComponent } from '@eg/share/dialog/alert.component';
import { GridComponent } from '@eg/share/grid/grid.component';
import { GridModule } from '@eg/share/grid/grid.module';
import { HoldsGridComponent } from '@eg/staff/share/holds/grid.component';

@Component({
    selector: 'eg-hold-group-event-mapping-info-dialog',
    imports: [GridModule, HoldsGridComponent],
    templateUrl: './hold-group-event-mapping-info-dialog.component.html',
})
export class HoldGroupEventMappingInfoDialogComponent extends AlertDialogComponent {

  @Input() eventId!: number;
  private _mappings!: IdlObject[];
  get mappings() {
      return this._mappings;
  }
  @Input() set mappings(arr: IdlObject[]) {
      this._mappings = arr;
      this.mappedIds = arr.map((abhem) => abhem.hold());
  }
  protected mappedIds!: number[];

  @ViewChild('mappedHoldsGrid') grid!: GridComponent;

}

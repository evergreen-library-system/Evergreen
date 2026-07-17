import { Component, Input, ViewChild, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-picklist-merge-dialog',
    templateUrl: './picklist-merge-dialog.component.html',
    imports: [
        AlertDialogComponent,
        FormsModule
    ]
})

export class PicklistMergeDialogComponent
    extends DialogComponent {
    private evt = inject(EventService);
    private net = inject(NetService);
    private auth = inject(AuthService);
    private modal: NgbModal;


  @Input() grid: any;
  listNames: string[];
  leadList: number;
  selectedLists: IdlObject[];

  @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;

  constructor() {
      const modal = inject(NgbModal);

      super(modal);

      this.modal = modal;
  }

  update() {
      this.selectedLists = this.grid.context.getSelectedRows();
      this.listNames = this.selectedLists.map( r => r.name() );
  }

  mergeLists() {
      const that = this;
      this.net.request(
          'open-ils.acq',
          'open-ils.acq.picklist.merge',
          this.auth.token(), this.leadList,
          this.selectedLists.map( list => list.id() ).filter(function(p) { return Number(p) !== Number(that.leadList); })
      ).subscribe(
          { next: (res) => {
              if (this.evt.parse(res)) {
                  console.error(res);
                  this.fail.open();
                  this.close(false);
              } else {
                  console.debug(res);
              }
          }, error: (err: unknown) => {
              console.error(err);
              this.fail.open();
              this.close(false);
          }, complete: () => this.close(true) }
      );
  }

}



import { Component, Input, ViewChild, inject } from '@angular/core';
import {forkJoin} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';


@Component({
    selector: 'eg-picklist-delete-dialog',
    templateUrl: './picklist-delete-dialog.component.html',
    imports: [
        AlertDialogComponent
    ]
})

export class PicklistDeleteDialogComponent
    extends DialogComponent {
    private evt = inject(EventService);
    private net = inject(NetService);
    private auth = inject(AuthService);
    private modal: NgbModal;


  @Input() grid: any;
  listNames: string[];

  @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;

  constructor() {
      const modal = inject(NgbModal);

      super(modal);

      this.modal = modal;
  }

  update() {
      this.listNames = this.grid.context.getSelectedRows().map( r => r.name() );
  }

  deleteList(list) {
      return this.net.request(
          'open-ils.acq',
          'open-ils.acq.picklist.delete',
          this.auth.token(),
          list.id()
      );
  }

  deleteLists() {
      const that = this;
      const observables = [];
      this.grid.context.getSelectedRows().forEach(function(r) {
          observables.push( that.deleteList(r) );
      });
      forkJoin(observables).subscribe(
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



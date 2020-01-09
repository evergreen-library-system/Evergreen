import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {Observable} from 'rxjs';
import { DialogComponent } from '@eg/share/dialog/dialog.component';

@Component({
    selector:'eg-user-dialog',
    templateUrl: './user-dialog.component.html'
})
export class UserDialogComponent extends DialogComponent implements OnInit {

    ngOnInit() {}

    constructor(
        private modal: NgbModal) {
        super(modal);
      }

      open(args?: NgbModalOptions): Observable<any> {
          if (!args) {
              args = {};
          }
          return super.open(args);
      }

      closeEditor() {
          this.close();
      }
}

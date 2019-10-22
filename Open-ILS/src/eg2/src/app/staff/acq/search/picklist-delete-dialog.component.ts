import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {Observable, forkJoin, from, empty, throwError} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  selector: 'eg-picklist-delete-dialog',
  templateUrl: './picklist-delete-dialog.component.html'
})

export class PicklistDeleteDialogComponent
  extends DialogComponent implements OnInit {

  @Input() grid: any;
  listNames: string[];

  @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;

  constructor(
    private idl: IdlService,
    private evt: EventService,
    private net: NetService,
    private auth: AuthService,
    private modal: NgbModal
  ) {
    super(modal);
  }

  ngOnInit() {
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
      (res) => {
        if (this.evt.parse(res)) {
          console.error(res);
          this.fail.open();
          this.close(false);
        } else {
          console.log(res);
        }
      },
      (err) => {
        console.error(err);
        this.fail.open();
        this.close(false);
      },
      () => this.close(true)
    );
  }
}



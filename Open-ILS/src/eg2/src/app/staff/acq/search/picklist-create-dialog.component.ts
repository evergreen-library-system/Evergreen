import {Component, Input, ViewChild, TemplateRef, OnInit, Renderer2} from '@angular/core';
import {Observable, from, throwError} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-picklist-create-dialog',
    templateUrl: './picklist-create-dialog.component.html'
})

export class PicklistCreateDialogComponent
    extends DialogComponent implements OnInit {

    selectionListName: String;

  @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;
  @ViewChild('dupe', { static: true }) private dupe: AlertDialogComponent;

  constructor(
    private renderer: Renderer2,
    private idl: IdlService,
    private evt: EventService,
    private net: NetService,
    private auth: AuthService,
    private modal: NgbModal
  ) {
      super(modal);
  }

  ngOnInit() {
      this.selectionListName = '';
  }

  update() {
      this.selectionListName = '';
      this.renderer.selectRootElement('#create-picklist-name').focus();
  }

  createList() {
      const picklist = this.idl.create('acqpl');
      picklist.owner(this.auth.user().id());
      picklist.name(this.selectionListName);
      this.net.request(
          'open-ils.acq',
          'open-ils.acq.picklist.create',
          this.auth.token(), picklist
      ).subscribe(
          (res) => {
              if (this.evt.parse(res)) {
                  console.error(res);
                  if (res.textcode === 'DATABASE_UPDATE_FAILED') {
                      // a duplicate name is not the only reason it could have failed,
                      // but that's the way to bet
                      this.dupe.open();
                  } else {
                      this.fail.open();
                  }
                  this.close(false);
              } else {
                  console.debug(res);
              }
          },
          (err: unknown) => {
              console.error(err);
              this.fail.open();
              this.close(false);
          },
          () => this.close(true)
      );
  }
}



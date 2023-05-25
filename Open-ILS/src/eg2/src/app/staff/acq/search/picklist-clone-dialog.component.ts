import {Component, Input, ViewChild, Renderer2} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-picklist-clone-dialog',
    templateUrl: './picklist-clone-dialog.component.html'
})

export class PicklistCloneDialogComponent
    extends DialogComponent {

  @Input() grid: any;
  selectionListName: String;
  leadListName: String;
  selections: IdlObject[];

  @ViewChild('fail', { static: true }) private fail: AlertDialogComponent;

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

  update() {
      this.leadListName = this.grid.context.getSelectedRows()[0].name();
      this.renderer.selectRootElement('#create-picklist-name').focus();
      this.selectionListName = 'Copy of ' + this.leadListName;
  }

  cloneList() {
      const picklist = this.idl.create('acqpl');
      picklist.owner(this.auth.user().id());
      picklist.name(this.selectionListName);
      this.net.request(
          'open-ils.acq',
          'open-ils.acq.picklist.clone',
          this.auth.token(),
          this.grid.context.getSelectedRows()[0].id(),
          this.selectionListName
      ).subscribe(
          (res) => {
              if (this.evt.parse(res)) {
                  console.error(res);
                  this.fail.open();
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



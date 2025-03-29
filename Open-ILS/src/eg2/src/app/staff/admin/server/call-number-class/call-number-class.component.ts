import { Component, OnInit, AfterViewInit, ViewChild, inject } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { NgbNav, NgbNavChangeEvent, NgbAlert, NgbNavModule } from '@ng-bootstrap/ng-bootstrap';
import { TranslateComponent } from '@eg/share/translate/translate.component';
import { lastValueFrom } from 'rxjs';
import { FormsModule } from '@angular/forms';
import { StaffCommonModule } from '@eg/staff/common.module';
import { ToastService } from '@eg/share/toast/toast.service';


@Component({
    standalone: true,
    selector: 'eg-call-number-class',
    templateUrl: './call-number-class.component.html',
    styleUrls: ['./call-number-class.component.css'],
    imports: [
        FormsModule,
        NgbNavModule,
        StaffCommonModule,
        TranslateComponent
    ]
})
export class CallNumberClassComponent implements OnInit, AfterViewInit {
    classes: IdlObject[] = [];
    splitFields: { [id:number]: string } = {};
    activeTab: string;

  @ViewChild('cnClassNav', { static: false }) cnClassNav: NgbNav;
  @ViewChild('updateSuccess', { static: false }) updateSuccess: NgbAlert;
  @ViewChild('updateFailed', { static: false }) updateFailed: NgbAlert;
  @ViewChild('translator', { static: true }) translator: TranslateComponent;

  private pcrud = inject(PcrudService);
  private toast = inject(ToastService);

  ngOnInit() {
      lastValueFrom(this.pcrud.retrieveAll('acnc',{ 'order_by': {'acnc': 'id'}},{atomic: true})).then(classes => {
          this.classes = classes;
          this.classes.forEach((cnClass) => this.getFields(cnClass));
          this.activeTab = 'nav' + this.classes[0].id();
          console.debug('Call number classifications: ', this.classes);
      });
  }

  ngAfterViewInit() {
      this.cnClassNav.select(this.activeTab);
  }

  onNavChange(evt: NgbNavChangeEvent) {
      this.activeTab = evt.nextId;
  }

  getRowCount(cnClass: IdlObject): number {
      const max_rows = 22;
      const room_to_edit = 3;
      const current_rows = cnClass.field().split(',').length + room_to_edit;
      if (current_rows > max_rows) {return max_rows;}

      return current_rows;
  }

  getFields(cnClass: IdlObject): string {
      return this.splitFields[cnClass.id()] = cnClass.field().replaceAll(',', '\n');
  }

  saveFields(cnClass: IdlObject, $event: any): void {
      if (!$event) {return;}
      this.splitFields[cnClass.id()] = $event.target.value;
      const whitespace_and_commas = new RegExp(/[\r\n\s,]+/gi);
      cnClass.field(this.splitFields[cnClass.id()].replace(whitespace_and_commas, ','));
      console.debug('Call number class admin: Updating fields for', cnClass.name(), cnClass.field());
  }

  save(cnClass: IdlObject): void {
      console.debug('Saving', cnClass);
      lastValueFrom(this.pcrud.update(cnClass)).then(
          ok => {
              this.toast.success($localize`:Call number classification admin save success:${cnClass.name()} saved`);
          },
          error => {
              this.toast.danger($localize`:Call number classification admin save success:Error: ${cnClass.name()} could not be updated`);
          }
      ).then(() => {
          // refresh view
          this.getFields(cnClass);
      });
  }

  translate(cnClass: IdlObject): void {
      this.translator.idlObject = cnClass;
      this.translator.fieldName = 'name';
      this.translator.open({size: 'lg'});
  }

}

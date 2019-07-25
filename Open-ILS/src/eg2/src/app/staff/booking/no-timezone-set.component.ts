import {Component} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
  selector: 'eg-no-timezone-set-dialog',
  templateUrl: './no-timezone-set.component.html'
})

/**
 * Dialog that warns users that there is no valid lib.timezone setting
 */
export class NoTimezoneSetComponent extends DialogComponent {
    openLSE(): void {
        window.open('/eg/staff/admin/local/asset/org_unit_settings', '_blank');
    }
}

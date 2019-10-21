import {Component, Input} from '@angular/core';
import {DomSanitizer} from '@angular/platform-browser';

const OPAC_BASE_URL = '/eg/opac/record';

@Component({
  selector: 'eg-opac-record-detail',
  templateUrl: 'opac.component.html'
})
export class OpacViewComponent {

    url; // SafeResourceUrlImpl

    _recordId: number;
    @Input() set recordId(id: number) {

        // Verify record ID is numeric only
        if (id && (id + '').match(/^\d+$/)) {
            this._recordId = id;
            this.url = this.sanitizer.bypassSecurityTrustResourceUrl(
                `${OPAC_BASE_URL}/${id}`);
        } else {
            this._recordId = null;
            this.url = null;
        }
    }

    get recordId(): number {
        return this._recordId;
    }

    constructor(private sanitizer: DomSanitizer) {}
}


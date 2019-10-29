import {Component, Input, Renderer2} from '@angular/core';
import {DomSanitizer} from '@angular/platform-browser';

const OPAC_BASE_URL = '/eg/opac/record';

@Component({
  selector: 'eg-opac-record-detail',
  templateUrl: 'opac.component.html'
})
export class OpacViewComponent {

    url; // SafeResourceUrlImpl
    loaded: boolean;

    _recordId: number;
    @Input() set recordId(id: number) {

        // Verify record ID is numeric only
        if (id && (id + '').match(/^\d+$/)) {
            this._recordId = id;
            this.url = this.sanitizer.bypassSecurityTrustResourceUrl(
                `${OPAC_BASE_URL}/${id}?readonly=1`);
        } else {
            this._recordId = null;
            this.url = null;
        }
    }

    get recordId(): number {
        return this._recordId;
    }

    constructor(
        private sanitizer: DomSanitizer,
        private renderer: Renderer2) {}

    handleLoad() {
        const iframe = this.renderer.selectRootElement('#opac-iframe');

        // 50 extra px adds enough space to avoid the scrollbar altogether
        const height = 50 + iframe.contentWindow.document.body.offsetHeight;

        iframe.style.height = `${height}px`;
        this.loaded = true;
    }
}


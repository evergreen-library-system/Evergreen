import {Component, OnInit, Input, ElementRef} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';

@Component({
  selector: 'eg-marc-html',
  // view is generated from MARC HTML
  template: '<ng-template></ng-template>'
})
export class MarcHtmlComponent implements OnInit {

    recId: number;
    initDone = false;

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.collectData();
        }
    }

    recType: string;
    @Input() set recordType(rtype: string) {
        this.recType = rtype;
    }

    constructor(
        private elm: ElementRef,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {
        this.initDone = true;
        this.collectData();
    }

    collectData() {
        if (!this.recId) { return; }

        let service = 'open-ils.search';
        let method = 'open-ils.search.biblio.record.html';
        const params: any[] = [this.recId];

        switch (this.recType) {

            case 'authority':
                method = 'open-ils.search.authority.to_html';
                break;

            case 'vandelay-authority':
                params.unshift(this.auth.token());
                service = 'open-ils.vandelay';
                method = 'open-ils.vandelay.queued_authority_record.html';
                break;

            case 'vandelay-bib':
                params.unshift(this.auth.token());
                service = 'open-ils.vandelay';
                method = 'open-ils.vandelay.queued_bib_record.html';
                break;
        }

        this.net.requestWithParamList(service, method, params)
        .toPromise().then(html => this.injectHtml(html));
    }

    injectHtml(html: string) {

        // Remove embedded labels and actions.
        html = html.replace(
            /<button onclick="window.print(.*?)<\/button>/, '');

        html = html.replace(/<title>(.*?)<\/title>/, '');

        // remove reference to nonexistant CSS file
        html = html.replace(/<link(.*?)\/>/, '');

        // there shouldn't be any, but while we're at it,
        // kill any embedded script tags
        html = html.replace(/<script(.*?)<\/script>/, '');

        this.elm.nativeElement.innerHTML = html;
    }
}



import { of } from 'rxjs';
import { Component, OnInit, Input } from '@angular/core';
import { OrgService } from '@eg/core/org.service';
import {
    BibRecordService, BibRecordSummary
} from '@eg/share/catalog/bib-record.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { CatalogService } from '@eg/share/catalog/catalog.service';
import { StaffCatalogService } from '@eg/staff/catalog/catalog.service';
import { ScriptService } from '@eg/share/util/script.service';

@Component({
    selector: 'eg-catalog-added-content',
    templateUrl: './added-content.component.html',
    styleUrls: ['./added-content.component.css']
})
export class AddedContentComponent implements OnInit {

    recId: number;
    initDone = false;
    added_content = false;
    added_content_sources: string[] = [];
    isbn = '';
    novelist: any = {};

  @Input() set recordId(id: number) {
        this.recId = id;
    }

  // Otherwise, we'll use the provided bib summary object.
  summary: BibRecordSummary;
  @Input() set bibSummary(s: any) {
      this.summary = s;
  }

  constructor(
    private bib: BibRecordService,
    private org: OrgService,
    private store: ServerStoreService,
    private cat: CatalogService,
    private staffCat: StaffCatalogService,
    private script: ScriptService
  ) { }

  ngOnInit() {
      // NovelistSelect settings
      this.store.getItemBatch([
          'staff.added_content.novelistselect.profile',
          'staff.added_content.novelistselect.passwd',
          'staff.added_content.novelistselect.version'
      ]).then(settings => {
          Object.keys(settings).forEach(k => {
              const key_parts = k.split('.');
              const key_part = key_parts[key_parts.length -1];

              if (settings[k] !== null) {
                  this.novelist[key_part] = settings[k];
              }
          });

          /* Do we show the tab? */
          if (this.novelist.profile && this.novelist.passwd) {
              this.added_content = true;
              this.added_content_sources.push('novelist');
          }

          if (!this.summary && this.recId) {
              return this.loadSummary()
                  .then(summary => this.summary = summary)
                  .then( _ => this.addNovelistScripts() );
          }

          if (this.summary || this.isbn) {
              return this.addNovelistScripts();
          }

      });
  }

  loadSummary(): Promise<any> {
      return this.bib.getBibSummary(
          this.recId,
          this.staffCat.searchContext.searchOrg.id(),
          true // isStaff
      ).toPromise();
  }

  addNovelistScripts(): Promise<any> {
      if (!this.added_content) {
          console.debug('Added content not enabled');
          return;
      }

      console.debug('Added content enabled');

      // lop off everything after the first space (i.e. remove format parentheticals)
      // then remove all dashes
      if (this.summary?.display?.isbn && !this.isbn) {
          this.isbn = this.summary.display.isbn[0].replace(' .*', '').replaceAll('-', '');
      }

      if (!this.isbn) { // welp, we got nothing...
          const ac_data_msg = document.getElementById('added-content-data');
          if (ac_data_msg) {
              ac_data_msg.style.display = 'none';
          }
          const ac_no_data_msg = document.getElementById('added-content-no-data');
          if (ac_no_data_msg) {
              ac_no_data_msg.style.display = 'inline';
          }
          return of().toPromise();
      }

      const params = {
          'isbn': this.isbn,
          'profile': this.novelist.profile,
          'passwd': this.novelist.passwd
      };

      /* Load the external and internal NoveList files from ScriptService */
      return this.script.loadScript('novelist').then(data => {
          console.debug('NoveList remote script loaded ', data);
      }).then(data => {
          // eslint-disable-next-line no-shadow
          this.script.loadScript('novelist-loading', params).then(data => {
              console.debug('NoveList local trigger script loaded', data);
          });
      });
  }
}



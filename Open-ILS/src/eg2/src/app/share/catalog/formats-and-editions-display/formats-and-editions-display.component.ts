import { Component, Input, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { BibRecordSummary } from '../bib-record.service';
import { CatalogService } from '../catalog.service';

@Component({
    selector: 'eg-formats-and-editions-display',
    standalone: true,
    imports: [CommonModule],
    templateUrl: './formats-and-editions-display.component.html',
    styleUrls: ['./formats-and-editions-display.component.css']
})
export class FormatsAndEditionsDisplayComponent {
  @Input() summary: BibRecordSummary;

  cat = inject(CatalogService);

  iconFormatLabel(code: string): string {
      return this.cat.iconFormatLabel(code);
  }
}

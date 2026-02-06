import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {BasketService} from './basket.service';
import {CatalogUrlService} from './catalog-url.service';
import {BibRecordService} from './bib-record.service';
import {UnapiService} from './unapi.service';
import {MarcHtmlComponent} from './marc-html.component';
import {BibDisplayFieldComponent} from './bib-display-field.component';


@NgModule({
    imports: [
        BibDisplayFieldComponent,
        EgCommonModule,
        MarcHtmlComponent,
    ],
    exports: [
        MarcHtmlComponent,
        BibDisplayFieldComponent
    ],
    providers: [
        CatalogUrlService,
        UnapiService,
        BibRecordService,
        BasketService
    ]
})

export class CatalogCommonModule {}

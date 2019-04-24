import {Component, OnInit, ViewChild} from '@angular/core';
import {StaffCatalogService} from './catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {SearchFormComponent} from './search-form.component';

@Component({
  templateUrl: 'browse.component.html'
})
export class BrowseComponent implements OnInit {

    @ViewChild('searchForm') searchForm: SearchFormComponent;

    constructor(
        private staffCat: StaffCatalogService,
        private basket: BasketService
    ) {}

    ngOnInit() {
        // A SearchContext provides all the data needed for browse.
        this.staffCat.createContext();

        // Cache the basket on page load.
        this.basket.getRecordIds();

        this.searchForm.searchTab = 'browse';
    }
}


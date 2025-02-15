import { ComponentFixture, TestBed } from '@angular/core/testing';

import { MetadataColumnComponent } from './metadata-column.component';

describe('MetadataColumnComponent', () => {
    let component: MetadataColumnComponent;
    let fixture: ComponentFixture<MetadataColumnComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [MetadataColumnComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(MetadataColumnComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
});

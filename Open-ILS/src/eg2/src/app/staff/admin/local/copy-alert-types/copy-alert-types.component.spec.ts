import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CopyAlertTypesComponent } from './copy-alert-types.component';

describe('CopyAlertTypesComponent', () => {
  let component: CopyAlertTypesComponent;
  let fixture: ComponentFixture<CopyAlertTypesComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      declarations: [ CopyAlertTypesComponent ]
    })
    .compileComponents();

    fixture = TestBed.createComponent(CopyAlertTypesComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});

import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {DateUtil} from '@eg/share/util/date';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import { NgForm } from '@angular/forms';

class DeskTotals {
    cash_payment = 0;
    check_payment = 0;
    credit_card_payment = 0;
    debit_card_payment = 0;
}

class UserTotals {
    forgive_payment = 0;
    work_payment = 0;
    credit_payment = 0;
    goods_payment = 0;
}

@Component({
    templateUrl: './cash-reports.component.html'
})
export class CashReportsComponent implements OnInit {
    initDone = false;
    deskPaymentDataSource: GridDataSource = new GridDataSource();
    userPaymentDataSource: GridDataSource = new GridDataSource();
    userDataSource: GridDataSource = new GridDataSource();
    deskIdlClass = 'mwps';
    userIdlClass = 'mups';
    selectedOrg = this.org.get(this.auth.user().ws_ou());
    startDate = new Date();
    endDate = new Date();
    deskTotals = new DeskTotals();
    userTotals = new UserTotals();
    disabledOrgs = [];
    activeTab = 'deskPayments';
    cellTextGenerator: GridCellTextGenerator;


    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;
    @ViewChild('deskPaymentGrid') deskPaymentGrid: GridComponent;
    @ViewChild('userPaymentGrid') userPaymentGrid: GridComponent;
    @ViewChild('userGrid') userGrid: GridComponent;
    @ViewChild('criteria') criteria: NgForm;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService) {}

    ngOnInit() {
        this.disabledOrgs = this.getFilteredOrgList();
        this.searchForData();

        this.cellTextGenerator = {
            card: row => row.user.card()
        };
    }

    searchForData() {
        this.userDataSource.data = [];
        this.fillGridData(this.deskIdlClass, 'deskPaymentDataSource',
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.money.org_unit.desk_payments',
                this.auth.token(), this.selectedOrg.id(),
                DateUtil.localYmdFromDate(this.startDate), DateUtil.localYmdFromDate(this.endDate)));

        this.fillGridData(this.userIdlClass, 'userPaymentDataSource',
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.money.org_unit.user_payments',
                this.auth.token(), this.selectedOrg.id(), this.startDate.toISOString().split('T')[0], this.endDate.toISOString().split('T')[0]));
    }

    fillGridData(idlClass, dataSource, data) {
        let dataForTotal;
        data.subscribe((result) => {
            if (idlClass === this.userIdlClass) {
                dataForTotal = this.getUserTotal(result);
                result.forEach((userObject, index) => {
                    result[index].user = userObject.usr();
                    result[index].usr(userObject.usr().usrname());
                    console.log('USER IS', userObject);
                });
            } else if(idlClass === this.deskIdlClass) {
                dataForTotal = this.getDeskTotal(result);
            }
            this[dataSource].data = result;
            this.eraseUserGrid();
        });
    }

    eraseUserGrid() {
        this.userDataSource.data = [];
    }

    getDeskTotal(idlObjects) {
        this.deskTotals = new DeskTotals();

        if (idlObjects.length > 0) {
            const idlObjectFormat = this.idl.create('mwps');
            idlObjects.forEach((idlObject) => {
                this.deskTotals['cash_payment'] += parseFloat(idlObject.cash_payment());
                this.deskTotals['check_payment'] += parseFloat(idlObject.check_payment());
                this.deskTotals['credit_card_payment'] += parseFloat(idlObject.credit_card_payment());
                this.deskTotals['debit_card_payment'] += parseFloat(idlObject.debit_card_payment());
            });
            idlObjectFormat.cash_payment(this.deskTotals['cash_payment']);
            idlObjectFormat.check_payment(this.deskTotals['check_payment']);
            idlObjectFormat.credit_card_payment(this.deskTotals['credit_card_payment']);
            idlObjectFormat.debit_card_payment(this.deskTotals['debit_card_payment']);
            return idlObjectFormat;
        }
    }

    getUserTotal(idlObjects) {
        this.userTotals = new UserTotals();
        if (idlObjects.length > 0) {
            const idlObjectFormat = this.idl.create('mups');
            idlObjects.forEach((idlObject, index) => {
                this.userTotals['forgive_payment'] += parseFloat(idlObject.forgive_payment());
                this.userTotals['work_payment'] += parseFloat(idlObject.work_payment());
                this.userTotals['credit_payment'] += parseFloat(idlObject.credit_payment());
                this.userTotals['goods_payment'] += parseFloat(idlObject.goods_payment());
                this.userDataSource.data = idlObjects[index].usr();
            });
            idlObjectFormat.forgive_payment(this.userTotals['forgive_payment']);
            idlObjectFormat.work_payment(this.userTotals['work_payment']);
            idlObjectFormat.credit_payment(this.userTotals['credit_payment']);
            idlObjectFormat.goods_payment(this.userTotals['goods_payment']);
            return idlObjectFormat;
        }
    }

    getFilteredOrgList() {
        const orgFilter = {canHaveUsers: false};
        return this.org.filterList(orgFilter, true);
    }

    onOrgChange(org) {
        this.selectedOrg = org;
        this.searchForData();
    }
}

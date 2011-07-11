
var rec_type = {
    BKS : { Type : /[at]{1}/,    BLvl : /[acdm]{1}/ },
    SER : { Type : /[a]{1}/,    BLvl : /[bsi]{1}/ },
    VIS : { Type : /[gkro]{1}/,    BLvl : /[abcdmsi]{1}/ },
    MIX : { Type : /[p]{1}/,    BLvl : /[cdi]{1}/ },
    MAP : { Type : /[ef]{1}/,    BLvl : /[abcdmsi]{1}/ },
    SCO : { Type : /[cd]{1}/,    BLvl : /[abcdmsi]{1}/ },
    REC : { Type : /[ij]{1}/,    BLvl : /[abcdmsi]{1}/ },
    COM : { Type : /[m]{1}/,    BLvl : /[abcdmsi]{1}/ },
    AUT : { Type : /[z]{1}/,    BLvl : /.{1}/ },
    MFHD : { Type : /[uvxy]{1}/,  BLvl : /.{1}/ }
};

var ff_pos = {
    Ctry : {
        _8 : {
            BKS : {start : 15, len : 3, def : ' ' },
            SER : {start : 15, len : 3, def : ' ' },
            VIS : {start : 15, len : 3, def : ' ' },
            MIX : {start : 15, len : 3, def : ' ' },
            MAP : {start : 15, len : 3, def : ' ' },
            SCO : {start : 15, len : 3, def : ' ' },
            REC : {start : 15, len : 3, def : ' ' },
            COM : {start : 15, len : 3, def : ' ' },
        }
    },
    Lang : {
        _8 : {
            BKS : {start : 35, len : 3, def : ' ' },
            SER : {start : 35, len : 3, def : ' ' },
            VIS : {start : 35, len : 3, def : ' ' },
            MIX : {start : 35, len : 3, def : ' ' },
            MAP : {start : 35, len : 3, def : ' ' },
            SCO : {start : 35, len : 3, def : ' ' },
            REC : {start : 35, len : 3, def : ' ' },
            COM : {start : 35, len : 3, def : ' ' },
        }
    },
    MRec : {
        _8 : {
            BKS : {start : 38, len : 1, def : ' ' },
            SER : {start : 38, len : 1, def : ' ' },
            VIS : {start : 38, len : 1, def : ' ' },
            MIX : {start : 38, len : 1, def : ' ' },
            MAP : {start : 38, len : 1, def : ' ' },
            SCO : {start : 38, len : 1, def : ' ' },
            REC : {start : 38, len : 1, def : ' ' },
            COM : {start : 38, len : 1, def : ' ' },
        }
    },
    DtSt : {
        _8 : {
            BKS : {start : 6, len : 1, def : ' ' },
            SER : {start : 6, len : 1, def : 'c' },
            VIS : {start : 6, len : 1, def : ' ' },
            MIX : {start : 6, len : 1, def : ' ' },
            MAP : {start : 6, len : 1, def : ' ' },
            SCO : {start : 6, len : 1, def : ' ' },
            REC : {start : 6, len : 1, def : ' ' },
            COM : {start : 6, len : 1, def : ' ' },
        }
    },
    Type : {
        ldr : {
            BKS : {start : 6, len : 1, def : 'a' },
            SER : {start : 6, len : 1, def : 'a' },
            VIS : {start : 6, len : 1, def : 'g' },
            MIX : {start : 6, len : 1, def : 'p' },
            MAP : {start : 6, len : 1, def : 'e' },
            SCO : {start : 6, len : 1, def : 'c' },
            REC : {start : 6, len : 1, def : 'i' },
            COM : {start : 6, len : 1, def : 'm' },
            AUT : {start : 6, len : 1, def : 'z' },
            MFHD : {start : 6, len : 1, def : 'y' }

        }
    },
    Ctrl : {
        ldr : {
            BKS : {start : 8, len : 1, def : ' ' },
            SER : {start : 8, len : 1, def : ' ' },
            VIS : {start : 8, len : 1, def : ' ' },
            MIX : {start : 8, len : 1, def : ' ' },
            MAP : {start : 8, len : 1, def : ' ' },
            SCO : {start : 8, len : 1, def : ' ' },
            REC : {start : 8, len : 1, def : ' ' },
            COM : {start : 8, len : 1, def : ' ' },
        }
    },
    BLvl : {
        ldr : {
            BKS : {start : 7, len : 1, def : 'm' },
            SER : {start : 7, len : 1, def : 's' },
            VIS : {start : 7, len : 1, def : 'm' },
            MIX : {start : 7, len : 1, def : 'c' },
            MAP : {start : 7, len : 1, def : 'm' },
            SCO : {start : 7, len : 1, def : 'm' },
            REC : {start : 7, len : 1, def : 'm' },
            COM : {start : 7, len : 1, def : 'm' },
        }
    },
    Desc : {
        ldr : {
            BKS : {start : 18, len : 1, def : ' ' },
            SER : {start : 18, len : 1, def : ' ' },
            VIS : {start : 18, len : 1, def : ' ' },
            MIX : {start : 18, len : 1, def : ' ' },
            MAP : {start : 18, len : 1, def : ' ' },
            SCO : {start : 18, len : 1, def : ' ' },
            REC : {start : 18, len : 1, def : ' ' },
            COM : {start : 18, len : 1, def : ' ' },
        }
    },
    Item : {
        ldr : {
            MFHD : {start : 18, len : 1, def : 'i' }
        }
    },
    ELvl : {
        ldr : {
            BKS : {start : 17, len : 1, def : ' ' },
            SER : {start : 17, len : 1, def : ' ' },
            VIS : {start : 17, len : 1, def : ' ' },
            MIX : {start : 17, len : 1, def : ' ' },
            MAP : {start : 17, len : 1, def : ' ' },
            SCO : {start : 17, len : 1, def : ' ' },
            REC : {start : 17, len : 1, def : ' ' },
            COM : {start : 17, len : 1, def : ' ' },
            AUT : {start : 17, len : 1, def : 'n' },
            MFHD : {start : 17, len : 1, def : 'u' }
        }
    },
    TMat : {
        _8 : {
            VIS : {start : 33, len : 1, def : ' ' },
        },
        _6 : {
            VIS : {start : 16, len : 1, def : ' ' },
        }
    },
    Indx : {
        _8 : {
            BKS : {start : 31, len : 1, def : '0' },
            MAP : {start : 31, len : 1, def : '0' },
        },
        _6 : {
            BKS : {start : 14, len : 1, def : '0' },
            MAP : {start : 14, len : 1, def : '0' },
        }
    },
    Date1 : {
        _8 : {
            BKS : {start : 7, len : 4, def : ' ' },
            SER : {start : 7, len : 4, def : ' ' },
            VIS : {start : 7, len : 4, def : ' ' },
            MIX : {start : 7, len : 4, def : ' ' },
            MAP : {start : 7, len : 4, def : ' ' },
            SCO : {start : 7, len : 4, def : ' ' },
            REC : {start : 7, len : 4, def : ' ' },
            COM : {start : 7, len : 4, def : ' ' },
        },
    },
    Date2 : {
        _8 : {
            BKS : {start : 11, len : 4, def : ' ' },
            SER : {start : 11, len : 4, def : '9' },
            VIS : {start : 11, len : 4, def : ' ' },
            MIX : {start : 11, len : 4, def : ' ' },
            MAP : {start : 11, len : 4, def : ' ' },
            SCO : {start : 11, len : 4, def : ' ' },
            REC : {start : 11, len : 4, def : ' ' },
            COM : {start : 11, len : 4, def : ' ' },
        },
    },
    LitF : {
        _8 : {
            BKS : {start : 33, len : 1, def : '0' },
        },
        _6 : {
            BKS : {start : 16, len : 1, def : '0' },
        }
    },
    Biog : {
        _8 : {
            BKS : {start : 34, len : 1, def : ' ' },
        },
        _6 : {
            BKS : {start : 17, len : 1, def : ' ' },
        }
    },
    Ills : {
        _8 : {
            BKS : {start : 18, len : 4, def : ' ' },
        },
        _6 : {
            BKS : {start : 1, len : 4, def : ' ' },
        }
    },
    Fest : {
        _8 : {
            BKS : {start : 30, len : 1, def : '0' },
        },
        _6 : {
            BKS : {start : 13, len : 1, def : '0' },
        }
    },
    Conf : {
        _8 : {
            BKS : {start : 24, len : 4, def : ' ' },
            SER : {start : 25, len : 3, def : ' ' },
        },
        _6 : {
            BKS : {start : 7, len : 4, def : ' ' },
            SER : {start : 8, len : 3, def : ' ' },
        }
    },
    GPub : {
        _8 : {
            BKS : {start : 28, len : 1, def : ' ' },
            SER : {start : 28, len : 1, def : ' ' },
            VIS : {start : 28, len : 1, def : ' ' },
            MAP : {start : 28, len : 1, def : ' ' },
            COM : {start : 28, len : 1, def : ' ' },
        },
        _6 : {
            BKS : {start : 11, len : 1, def : ' ' },
            SER : {start : 11, len : 1, def : ' ' },
            VIS : {start : 11, len : 1, def : ' ' },
            MAP : {start : 11, len : 1, def : ' ' },
            COM : {start : 11, len : 1, def : ' ' },
        }
    },
    Audn : {
        _8 : {
            BKS : {start : 22, len : 1, def : ' ' },
            SER : {start : 22, len : 1, def : ' ' },
            VIS : {start : 22, len : 1, def : ' ' },
            SCO : {start : 22, len : 1, def : ' ' },
            REC : {start : 22, len : 1, def : ' ' },
            COM : {start : 22, len : 1, def : ' ' },
        },
        _6 : {
            BKS : {start : 5, len : 1, def : ' ' },
            SER : {start : 5, len : 1, def : ' ' },
            VIS : {start : 5, len : 1, def : ' ' },
            SCO : {start : 5, len : 1, def : ' ' },
            REC : {start : 5, len : 1, def : ' ' },
            COM : {start : 5, len : 1, def : ' ' },
        }
    },
    Form : {
        _8 : {
            BKS : {start : 23, len : 1, def : ' ' },
            SER : {start : 23, len : 1, def : ' ' },
            VIS : {start : 29, len : 1, def : ' ' },
            MIX : {start : 23, len : 1, def : ' ' },
            MAP : {start : 29, len : 1, def : ' ' },
            SCO : {start : 23, len : 1, def : ' ' },
            REC : {start : 23, len : 1, def : ' ' },
        },
        _6 : {
            BKS : {start : 6, len : 1, def : ' ' },
            SER : {start : 6, len : 1, def : ' ' },
            VIS : {start : 12, len : 1, def : ' ' },
            MIX : {start : 6, len : 1, def : ' ' },
            MAP : {start : 12, len : 1, def : ' ' },
            SCO : {start : 6, len : 1, def : ' ' },
            REC : {start : 6, len : 1, def : ' ' },
        }
    },
    'S/L' : {
        _8 : {
            SER : {start : 34, len : 1, def : '0' },
        },
        _6 : {
            SER : {start : 17, len : 1, def : '0' },
        }
    },
    'Alph' : {
        _8 : {
            SER : {start : 33, len : 1, def : ' ' },
        },
        _6 : {
            SER : {start : 16, len : 1, def : ' ' },
        }
    },
    "GeoDiv" : {
        "_8" : {
            "AUT" : {"start" : 6, "len" : 1, "def" : ' ' }
        }
    },
    "Roman" : {
        "_8" : {
            "AUT" : {"start" : 7, "len" : 1, "def" : ' ' }
        }
    },
    "CatLang" : {
        "_8" : {
            "AUT" : {"start" : 8, "len" : 1, "def" : ' ' }
        }
    },
    "Kind" : {
        "_8" : {
            "AUT" : {"start" : 9, "len" : 1, "def" : ' ' }
        }
    },
    "Rules" : {
        "_8" : {
            "AUT" : {"start" : 10, "len" : 1, "def" : ' ' }
        }
    },
    "SHSys" : {
        "_8" : {
            "AUT" : {"start" : 11, "len" : 1, "def" : ' ' }
        }
    },
    "SerType" : {
        "_8" : {
            "AUT" : {"start" : 12, "len" : 1, "def" : ' ' }
        }
    },
    "SerNum" : {
        "_8" : {
            "AUT" : {"start" : 13, "len" : 1, "def" : ' ' }
        }
    },
    "HeadMain" : {
        "_8" : {
            "AUT" : {"start" : 14, "len" : 1, "def" : ' ' }
        }
    },
    "HeadSubj" : {
        "_8" : {
            "AUT" : {"start" : 15, "len" : 1, "def" : ' ' }
        }
    },
    "HeadSer" : {
        "_8" : {
            "AUT" : {"start" : 16, "len" : 1, "def" : ' ' }
        }
    },
    "TypeSubd" : {
        "_8" : {
            "AUT" : {"start" : 17, "len" : 1, "def" : ' ' }
        }
    },
    "TypeGov" : {
        "_8" : {
            "AUT" : {"start" : 28, "len" : 1, "def" : ' ' }
        }
    },
    "RefEval" : {
        "_8" : {
            "AUT" : {"start" : 29, "len" : 1, "def" : ' ' }
        }
    },
    "RecUpd" : {
        "_8" : {
            "AUT" : {"start" : 31, "len" : 1, "def" : ' ' }
        }
    },
    "NameDiff" : {
        "_8" : {
            "AUT" : {"start" : 32, "len" : 1, "def" : ' ' }
        }
    },
    "Level" : {
        "_8" : {
            "AUT" : {"start" : 33, "len" : 1, "def" : ' ' }
        }
    },
    "ModRec" : {
        "_8" : {
            "AUT" : {"start" : 38, "len" : 1, "def" : ' ' }
        }
    },
    "CatSrc" : {
        "_8" : {
            "AUT" : {"start" : 39, "len" : 1, "def" : ' ' }
        }
    }
};


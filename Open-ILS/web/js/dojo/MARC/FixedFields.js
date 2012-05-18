/* ---------------------------------------------------------------------------
 * Copyright (C) 2011  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource["MARC.FixedFields"]) {

    dojo.require('MARC.Record');

    dojo._hasResource["MARC.FixedFields"] = true;
    dojo.provide("MARC.FixedFields");

    MARC.Record._recType = {
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

    MARC.Record._ff_pos = {
        AccM : {
            _8 : {
                SCO : {start: 24, len : 6, def : ' ' },
                REC : {start: 24, len : 6, def : ' ' }
            },
            _6 : {
                SCO : {start: 7, len : 6, def : ' ' },
                REC : {start: 7, len : 6, def : ' ' }
            }
        },
        Alph : {
            _8 : {
                SER : {start : 33, len : 1, def : ' ' }
            },
            _6 : {
                SER : {start : 16, len : 1, def : ' ' }
            }
        },
        Audn : {
            _8 : {
                BKS : {start : 22, len : 1, def : ' ' },
                SER : {start : 22, len : 1, def : ' ' },
                VIS : {start : 22, len : 1, def : ' ' },
                SCO : {start : 22, len : 1, def : ' ' },
                REC : {start : 22, len : 1, def : ' ' },
                COM : {start : 22, len : 1, def : ' ' }
            },
            _6 : {
                BKS : {start : 5, len : 1, def : ' ' },
                SER : {start : 5, len : 1, def : ' ' },
                VIS : {start : 5, len : 1, def : ' ' },
                SCO : {start : 5, len : 1, def : ' ' },
                REC : {start : 5, len : 1, def : ' ' },
                COM : {start : 5, len : 1, def : ' ' }
            }
        },
        Biog : {
            _8 : {
                BKS : {start : 34, len : 1, def : ' ' }
            },
            _6 : {
                BKS : {start : 17, len : 1, def : ' ' }
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
                COM : {start : 7, len : 1, def : 'm' }
            }
        },
        Comp : {
            _8 : {
                SCO : {start : 18, len : 2, def : 'uu'},
                REC : {start : 18, len : 2, def : 'uu'}
            },
            _6 : {
                SCO : {start : 1, len : 2, def : 'uu'},
                REC : {start : 1, len : 2, def : 'uu'}
            },
        },
        Conf : {
            _8 : {
                BKS : {start : 29, len : 1, def : '0' },
                SER : {start : 29, len : 1, def : '0' }
            },
            _6 : {
                BKS : {start : 11, len : 1, def : '0' },
                SER : {start : 11, len : 1, def : '0' }
            }
        },
        Cont : {
            _8 : {
                BKS : {start : 24, len : 4, def : ' ' },
                SER : {start : 25, len : 3, def : ' ' }
            },
            _6 : {
                BKS : {start : 7, len : 4, def : ' ' },
                SER : {start : 8, len : 3, def : ' ' }
            }
        },
        CrTp : {
            _8 : {
                MAP : {start: 25, len : 1, def : 'a' }
            },
            _6 : { 
                MAP : {start : 8, len : 1, def : 'a' }
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
                COM : {start : 8, len : 1, def : ' ' }
            }
        },
        Ctry : {
                _8 : {
                    BKS : {start : 15, len : 3, def : ' ' },
                    SER : {start : 15, len : 3, def : ' ' },
                    VIS : {start : 15, len : 3, def : ' ' },
                    MIX : {start : 15, len : 3, def : ' ' },
                    MAP : {start : 15, len : 3, def : ' ' },
                    SCO : {start : 15, len : 3, def : ' ' },
                    REC : {start : 15, len : 3, def : ' ' },
                    COM : {start : 15, len : 3, def : ' ' }
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
                COM : {start : 7, len : 4, def : ' ' }
            }
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
                COM : {start : 11, len : 4, def : ' ' }
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
                COM : {start : 18, len : 1, def : ' ' }
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
                COM : {start : 6, len : 1, def : ' ' }
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
        EntW : {
            _8 : {
                SER : {start : 24, len : 1, def : ' '}
            },
            _6 : {
                SER : {start : 7, len : 1, def : ' '}
            }
        },
        Fest : {
            _8 : {
                BKS : {start : 30, len : 1, def : '0' }
            },
            _6 : {
                BKS : {start : 13, len : 1, def : '0' }
            }
        },
        File : {
            _8 : {
                COM : {start: 26, len : 1, def : 'u' }
            },
            _6 : {
                COM : {start: 9, len : 1, def : 'u' }
            }
        },
        FMus : {
            _8 : {
                SCO : {start : 20, len : 1, def : 'u'},
                REC : {start : 20, len : 1, def : 'n'}
            },
            _6 : {
                SCO : {start : 3, len : 1, def : 'u'},
                REC : {start : 3, len : 1, def : 'n'}
            },
        },
        Form : {
            _8 : {
                BKS : {start : 23, len : 1, def : ' ' },
                SER : {start : 23, len : 1, def : ' ' },
                VIS : {start : 29, len : 1, def : ' ' },
                MIX : {start : 23, len : 1, def : ' ' },
                MAP : {start : 29, len : 1, def : ' ' },
                SCO : {start : 23, len : 1, def : ' ' },
                REC : {start : 23, len : 1, def : ' ' }
            },
            _6 : {
                BKS : {start : 6, len : 1, def : ' ' },
                SER : {start : 6, len : 1, def : ' ' },
                VIS : {start : 12, len : 1, def : ' ' },
                MIX : {start : 6, len : 1, def : ' ' },
                MAP : {start : 12, len : 1, def : ' ' },
                SCO : {start : 6, len : 1, def : ' ' },
                REC : {start : 6, len : 1, def : ' ' }
            }
        },
        Freq : {
            _8 : {
                SER : {start : 18, len : 1, def : ' '}
            },
            _6 : {
                SER : {start : 1, len : 1, def : ' '}
            }
        },
        GPub : {
            _8 : {
                BKS : {start : 28, len : 1, def : ' ' },
                SER : {start : 28, len : 1, def : ' ' },
                VIS : {start : 28, len : 1, def : ' ' },
                MAP : {start : 28, len : 1, def : ' ' },
                COM : {start : 28, len : 1, def : ' ' }
            },
            _6 : {
                BKS : {start : 11, len : 1, def : ' ' },
                SER : {start : 11, len : 1, def : ' ' },
                VIS : {start : 11, len : 1, def : ' ' },
                MAP : {start : 11, len : 1, def : ' ' },
                COM : {start : 11, len : 1, def : ' ' }
            }
        },
        Ills : {
            _8 : {
                BKS : {start : 18, len : 4, def : ' ' }
            },
            _6 : {
                BKS : {start : 1, len : 4, def : ' ' }
            }
        },
        Indx : {
            _8 : {
                BKS : {start : 31, len : 1, def : '0' },
                MAP : {start : 31, len : 1, def : '0' }
            },
            _6 : {
                BKS : {start : 14, len : 1, def : '0' },
                MAP : {start : 14, len : 1, def : '0' }
            }
        },
        Item : {
            ldr : {
                MFHD : {start : 18, len : 1, def : 'i' }
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
                COM : {start : 35, len : 3, def : ' ' }
            }
        },
        LitF : {
            _8 : {
                BKS : {start : 33, len : 1, def : '0' }
            },
            _6 : {
                BKS : {start : 16, len : 1, def : '0' }
            }
        },
        LTxt : {
            _8 : {
                SCO : {start : 30, len : 2, def : 'n'},
                REC : {start : 30, len : 2, def : ' '}
            },
            _6 : {
                SCO : {start : 13, len : 2, def : 'n'},
                REC : {start : 13, len : 2, def : ' '}
            },
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
                COM : {start : 38, len : 1, def : ' ' }
            }
        },
        Orig : {
            _8 : {
                SER : {start : 22, len : 1, def : ' '}
            },
            _6 : {
                SER : {start: 5, len : 1, def: ' '}
            }
        },
        Part : {
            _8 : {
                SCO : {start : 21, len : 1, def : ' '},
                REC : {start : 21, len : 1, def : 'n'}
            },
            _6 : {
                SCO : {start : 4, len : 1, def : ' '},
                REC : {start : 4, len : 1, def : 'n'}
            },
        },
        Proj : {
            _8 : {
                MAP : {start : 22, len : 2, def : ' ' }
            },
            _6 : {
                MAP: {start : 5, len : 2, def : ' ' }
            }
        },
        RecStat : {
            ldr : {
                BKS : {start : 5, len : 1, def : 'n' },
                SER : {start : 5, len : 1, def : 'n' },
                VIS : {start : 5, len : 1, def : 'n' },
                MIX : {start : 5, len : 1, def : 'n' },
                MAP : {start : 5, len : 1, def : 'n' },
                SCO : {start : 5, len : 1, def : 'n' },
                REC : {start : 5, len : 1, def : 'n' },
                COM : {start : 5, len : 1, def : 'n' },
                MFHD: {start : 5, len : 1, def : 'n' },
                AUT : {start : 5, len : 1, def : 'n' }
            }
        },
        Regl : {
            _8 : {
                SER : {start : 19, len : 1, def : ' '}
            },
            _6 : {
                SER : {start : 2, len : 1, def : ' '}
            }
        },
        Relf : {
            _8 : {
                MAP : {start: 18, len : 4, def : ' '}
            },
            _6 : {
                MAP : {start: 1, len : 4, def : ' '}
            }
        },
        'S/L' : {
            _8 : {
                SER : {start : 34, len : 1, def : '0' }
            },
            _6 : {
                SER : {start : 17, len : 1, def : '0' }
            }
        },
        SpFM : {
            _8 : {
                MAP : {start: 33, len : 2, def : ' ' }
            },
            _6 : {
                MAP : {start: 16, len : 2, def : ' '}
            }
        },
        Srce : {
            _8 : {
                BKS : {start : 39, len : 1, def : 'd' },
                SER : {start : 39, len : 1, def : 'd' },
                VIS : {start : 39, len : 1, def : 'd' },
                SCO : {start : 39, len : 1, def : 'd' },
                REC : {start : 39, len : 1, def : 'd' },
                COM : {start : 39, len : 1, def : 'd' },
                MFHD : {start : 39, len : 1, def : 'd' },
                "AUT" : {"start" : 39, "len" : 1, "def" : 'd' }
            }
        },
        SrTp : {
            _8 : {
                SER : {start : 21, len : 1, def : ' '}
            },
            _6 : {
                SER : {start : 4, len : 1, def : ' '}
            }
        },
        Tech : {
            _8 : {
                VIS : {start : 34, len : 1, def : ' '}
            },
            _6 : {
                VIS : {start : 17, len : 1, def : ' '}
            }
        },
        Time : {
            _8 : {
                VIS : {start : 18, len : 3, def : ' '}
            },
            _6 : {
                VIS : {start : 1, len : 3, def : ' '}
            }
        },
        TMat : {
            _8 : {
                VIS : {start : 33, len : 1, def : ' ' }
            },
            _6 : {
                VIS : {start : 16, len : 1, def : ' ' }
            }
        },
        TrAr : {
            _8 : {
                SCO : {start : 33, len : 1, def : ' ' },
                REC : {start : 33, len : 1, def : 'n' }
            },
            _6 : {
                SCO : {start : 16, len : 1, def : ' ' },
                REC : {start : 16, len : 1, def : 'n' }
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
         "Subj" : {
             "_8" : {
                 "AUT" : {"start" : 11, "len" : 1, "def" : ' ' }
             }
         },
         "Series" : {
             "_8" : {
                 "AUT" : {"start" : 12, "len" : 1, "def" : ' ' }
             }
         },
         "SerNum" : {
             "_8" : {
                 "AUT" : {"start" : 13, "len" : 1, "def" : ' ' }
             }
         },
         "NameUse" : {
             "_8" : {
                 "AUT" : {"start" : 14, "len" : 1, "def" : ' ' }
             }
         },
         "SubjUse" : {
             "_8" : {
                 "AUT" : {"start" : 15, "len" : 1, "def" : ' ' }
             }
         },
         "SerUse" : {
             "_8" : {
                 "AUT" : {"start" : 16, "len" : 1, "def" : ' ' }
             }
         },
         "TypeSubd" : {
             "_8" : {
                 "AUT" : {"start" : 17, "len" : 1, "def" : ' ' }
             }
         },
         "GovtAgn" : {
             "_8" : {
                 "AUT" : {"start" : 28, "len" : 1, "def" : ' ' }
             }
         },
         "RefStatus" : {
             "_8" : {
                 "AUT" : {"start" : 29, "len" : 1, "def" : ' ' }
             }
         },
         "UpdStatus" : {
             "_8" : {
                 "AUT" : {"start" : 31, "len" : 1, "def" : ' ' }
             }
         },
         "Name" : {
             "_8" : {
                 "AUT" : {"start" : 32, "len" : 1, "def" : ' ' }
             }
         },
         "Status" : {
             "_8" : {
                 "AUT" : {"start" : 33, "len" : 1, "def" : ' ' }
             }
         },
         "ModRec" : {
             "_8" : {
                 "AUT" : {"start" : 38, "len" : 1, "def" : ' ' }
             }
         },
         "Source" : {
             "_8" : {
                 "AUT" : {"start" : 39, "len" : 1, "def" : ' ' }
             }
         }
    };
    
    MARC.Record._physical_characteristics = {
        c : {
            label     : "Electronic Resource",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    a : "Tape Cartridge",
                            b : "Chip cartridge",
                            c : "Computer optical disk cartridge",
                            f : "Tape cassette",
                            h : "Tape reel",
                            j : "Magnetic disk",
                            m : "Magneto-optical disk",
                            o : "Optical disk",
                            r : "Remote",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    a : "One color",
                            b : "Black-and-white",
                            c : "Multicolored",
                            g : "Gray scale",
                            m : "Mixed",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "3 1/2 in.",
                            e : "12 in.",
                            g : "4 3/4 in. or 12 cm.",
                            i : "1 1/8 x 2 3/8 in.",
                            j : "3 7/8 x 2 1/2 in.",
                            n : "Not applicable",
                            o : "5 1/4 in.",
                            u : "Unknown",
                            v : "8 in.",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Sound",
                    values: {    ' ' : "No sound (Silent)",
                            a   : "Sound",
                            u   : "Unknown"
                    }
                },
                g : {    start : 6,
                    len   : 3,
                    label : "Image bit depth",
                    values: {    mmm   : "Multiple",
                            nnn   : "Not applicable",
                            '---' : "Unknown"
                    }
                },
                h : {    start : 9,
                    len   : 1,
                    label : "File formats",
                    values: {    a : "One file format",
                            m : "Multiple file formats",
                            u : "Unknown"
                    }
                },
                i : {    start : 10,
                    len   : 1,
                    label : "Quality assurance target(s)",
                    values: {    a : "Absent",
                            n : "Not applicable",
                            p : "Present",
                            u : "Unknown"
                    }
                },
                j : {    start : 11,
                    len   : 1,
                    label : "Antecedent/Source",
                    values: {    a : "File reproduced from original",
                            b : "File reproduced from microform",
                            c : "File reproduced from electronic resource",
                            d : "File reproduced from an intermediate (not microform)",
                            m : "Mixed",
                            n : "Not applicable",
                            u : "Unknown"
                    }
                },
                k : {    start : 12,
                    len   : 1,
                    label : "Level of compression",
                    values: {    a : "Uncompressed",
                            b : "Lossless",
                            d : "Lossy",
                            m : "Mixed",
                            u : "Unknown"
                    }
                },
                l : {    start : 13,
                    len   : 1,
                    label : "Reformatting quality",
                    values: {    a : "Access",
                            n : "Not applicable",
                            p : "Preservation",
                            r : "Replacement",
                            u : "Unknown"
                    }
                }
            }
        },
        d : {
            label     : "Globe",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    a : "Celestial globe",
                            b : "Planetary or lunar globe",
                            c : "Terrestrial globe",
                            e : "Earth moon globe",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    a : "One color",
                            c : "Multicolored"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Physical medium",
                    values: {    a : "Paper",
                            b : "Wood",
                            c : "Stone",
                            d : "Metal",
                            e : "Synthetics",
                            f : "Skins",
                            g : "Textile",
                            p : "Plaster",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Type of reproduction",
                    values: {    f : "Facsimile",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        a : {
            label     : "Map",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    d : "Atlas",
                            g : "Diagram",
                            j : "Map",
                            k : "Profile",
                            q : "Model",
                            r : "Remote-sensing image",
                            s : "Section",
                            u : "Unspecified",
                            y : "View",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    a : "One color",
                            c : "Multicolored"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Physical medium",
                    values: {    a : "Paper",
                            b : "Wood",
                            c : "Stone",
                            d : "Metal",
                            e : "Synthetics",
                            f : "Skins",
                            g : "Textile",
                            p : "Plaster",
                            q : "Flexible base photographic medium, positive",
                            r : "Flexible base photographic medium, negative",
                            s : "Non-flexible base photographic medium, positive",
                            t : "Non-flexible base photographic medium, negative",
                            u : "Unknown",
                            y : "Other photographic medium",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Type of reproduction",
                    values: {    f : "Facsimile",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Production/reproduction details",
                    values: {    a : "Photocopy, blueline print",
                            b : "Photocopy",
                            c : "Pre-production",
                            d : "Film",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Positive/negative",
                    values: {    a : "Positive",
                            b : "Negative",
                            m : "Mixed",
                            n : "Not applicable"
                    }
                }
            }
        },
        h : {
            label     : "Microform",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    a : "Aperture card",
                            b : "Microfilm cartridge",
                            c : "Microfilm cassette",
                            d : "Microfilm reel",
                            e : "Microfiche",
                            f : "Microfiche cassette",
                            g : "Microopaque",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Positive/negative",
                    values: {    a : "Positive",
                            b : "Negative",
                            m : "Mixed",
                            u : "Unknown"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "8 mm.",
                            e : "16 mm.",
                            f : "35 mm.",
                            g : "70mm.",
                            h : "105 mm.",
                            l : "3 x 5 in. (8 x 13 cm.)",
                            m : "4 x 6 in. (11 x 15 cm.)",
                            o : "6 x 9 in. (16 x 23 cm.)",
                            p : "3 1/4 x 7 3/8 in. (9 x 19 cm.)",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 4,
                    label : "Reduction ratio range/Reduction ratio",
                    values: {    a : "Low (1-16x)",
                            b : "Normal (16-30x)",
                            c : "High (31-60x)",
                            d : "Very high (61-90x)",
                            e : "Ultra (90x-)",
                            u : "Unknown",
                            v : "Reduction ratio varies"
                    }
                },
                g : {    start : 9,
                    len   : 1,
                    label : "Color",
                    values: {    b : "Black-and-white",
                            c : "Multicolored",
                            m : "Mixed",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 10,
                    len   : 1,
                    label : "Emulsion on film",
                    values: {    a : "Silver halide",
                            b : "Diazo",
                            c : "Vesicular",
                            m : "Mixed",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 11,
                    len   : 1,
                    label : "Quality assurance target(s)",
                    values: {    a : "1st gen. master",
                            b : "Printing master",
                            c : "Service copy",
                            m : "Mixed generation",
                            u : "Unknown"
                    }
                },
                j : {    start : 12,
                    len   : 1,
                    label : "Base of film",
                    values: {    a : "Safety base, undetermined",
                            c : "Safety base, acetate undetermined",
                            d : "Safety base, diacetate",
                            l : "Nitrate base",
                            m : "Mixed base",
                            n : "Not applicable",
                            p : "Safety base, polyester",
                            r : "Safety base, mixed",
                            t : "Safety base, triacetate",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        m : {
            label     : "Motion Picture",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    a : "Film cartridge",
                            f : "Film cassette",
                            r : "Film reel",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    b : "Black-and-white",
                            c : "Multicolored",
                            h : "Hand-colored",
                            m : "Mixed",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Motion picture presentation format",
                    values: {    a : "Standard sound aperture, reduced frame",
                            b : "Nonanamorphic (wide-screen)",
                            c : "3D",
                            d : "Anamorphic (wide-screen)",
                            e : "Other-wide screen format",
                            f : "Standard. silent aperture, full frame",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Sound on medium or separate",
                    values: {    a : "Sound on medium",
                            b : "Sound separate from medium",
                            u : "Unknown"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Medium for sound",
                    values: {    a : "Optical sound track on motion picture film",
                            b : "Magnetic sound track on motion picture film",
                            c : "Magnetic audio tape in cartridge",
                            d : "Sound disc",
                            e : "Magnetic audio tape on reel",
                            f : "Magnetic audio tape in cassette",
                            g : "Optical and magnetic sound track on film",
                            h : "Videotape",
                            i : "Videodisc",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "Standard 8 mm.",
                            b : "Super 8 mm./single 8 mm.",
                            c : "9.5 mm.",
                            d : "16 mm.",
                            e : "28 mm.",
                            f : "35 mm.",
                            g : "70 mm.",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 8,
                    len   : 1,
                    label : "Configuration of playback channels",
                    values: {    k : "Mixed",
                            m : "Monaural",
                            n : "Not applicable",
                            q : "Multichannel, surround or quadraphonic",
                            s : "Stereophonic",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                j : {    start : 9,
                    len   : 1,
                    label : "Production elements",
                    values: {    a : "Work print",
                            b : "Trims",
                            c : "Outtakes",
                            d : "Rushes",
                            e : "Mixing tracks",
                            f : "Title bands/inter-title rolls",
                            g : "Production rolls",
                            n : "Not applicable",
                            z : "Other"
                    }
                }
            }
        },
        k : {
            label     : "Non-projected Graphic",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    c : "Collage",
                            d : "Drawing",
                            e : "Painting",
                            f : "Photo-mechanical print",
                            g : "Photonegative",
                            h : "Photoprint",
                            i : "Picture",
                            j : "Print",
                            l : "Technical drawing",
                            n : "Chart",
                            o : "Flash/activity card",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    a : "One color",
                            b : "Black-and-white",
                            c : "Multicolored",
                            h : "Hand-colored",
                            m : "Mixed",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Primary support material",
                    values: {    a : "Canvas",
                            b : "Bristol board",
                            c : "Cardboard/illustration board",
                            d : "Glass",
                            e : "Synthetics",
                            f : "Skins",
                            g : "Textile",
                            h : "Metal",
                            m : "Mixed collection",
                            o : "Paper",
                            p : "Plaster",
                            q : "Hardboard",
                            r : "Porcelain",
                            s : "Stone",
                            t : "Wood",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Secondary support material",
                    values: {    a : "Canvas",
                            b : "Bristol board",
                            c : "Cardboard/illustration board",
                            d : "Glass",
                            e : "Synthetics",
                            f : "Skins",
                            g : "Textile",
                            h : "Metal",
                            m : "Mixed collection",
                            o : "Paper",
                            p : "Plaster",
                            q : "Hardboard",
                            r : "Porcelain",
                            s : "Stone",
                            t : "Wood",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        g : {
            label     : "Projected Graphic",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    c : "Film cartridge",
                            d : "Filmstrip",
                            f : "Film filmstrip type",
                            o : "Filmstrip roll",
                            s : "Slide",
                            t : "Transparency",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    b : "Black-and-white",
                            c : "Multicolored",
                            h : "Hand-colored",
                            m : "Mixed",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Base of emulsion",
                    values: {    d : "Glass",
                            e : "Synthetics",
                            j : "Safety film",
                            k : "Film base, other than safety film",
                            m : "Mixed collection",
                            o : "Paper",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Sound on medium or separate",
                    values: {    a : "Sound on medium",
                            b : "Sound separate from medium",
                            u : "Unknown"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Medium for sound",
                    values: {    a : "Optical sound track on motion picture film",
                            b : "Magnetic sound track on motion picture film",
                            c : "Magnetic audio tape in cartridge",
                            d : "Sound disc",
                            e : "Magnetic audio tape on reel",
                            f : "Magnetic audio tape in cassette",
                            g : "Optical and magnetic sound track on film",
                            h : "Videotape",
                            i : "Videodisc",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "Standard 8 mm.",
                            b : "Super 8 mm./single 8 mm.",
                            c : "9.5 mm.",
                            d : "16 mm.",
                            e : "28 mm.",
                            f : "35 mm.",
                            g : "70 mm.",
                            j : "2 x 2 in. (5 x 5 cm.)",
                            k : "2 1/4 x 2 1/4 in. (6 x 6 cm.)",
                            s : "4 x 5 in. (10 x 13 cm.)",
                            t : "5 x 7 in. (13 x 18 cm.)",
                            v : "8 x 10 in. (21 x 26 cm.)",
                            w : "9 x 9 in. (23 x 23 cm.)",
                            x : "10 x 10 in. (26 x 26 cm.)",
                            y : "7 x 7 in. (18 x 18 cm.)",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 8,
                    len   : 1,
                    label : "Secondary support material",
                    values: {    c : "Cardboard",
                            d : "Glass",
                            e : "Synthetics",
                            h : "metal",
                            j : "Metal and glass",
                            k : "Synthetics and glass",
                            m : "Mixed collection",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        r : {
            label     : "Remote-sensing Image",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: { u : "Unspecified" }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Altitude of sensor",
                    values: {    a : "Surface",
                            b : "Airborne",
                            c : "Spaceborne",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Attitude of sensor",
                    values: {    a : "Low oblique",
                            b : "High oblique",
                            c : "Vertical",
                            n : "Not applicable",
                            u : "Unknown"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Cloud cover",
                    values: {    0 : "0-09%",
                            1 : "10-19%",
                            2 : "20-29%",
                            3 : "30-39%",
                            4 : "40-49%",
                            5 : "50-59%",
                            6 : "60-69%",
                            7 : "70-79%",
                            8 : "80-89%",
                            9 : "90-100%",
                            n : "Not applicable",
                            u : "Unknown"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Platform construction type",
                    values: {    a : "Balloon",
                            b : "Aircraft-low altitude",
                            c : "Aircraft-medium altitude",
                            d : "Aircraft-high altitude",
                            e : "Manned spacecraft",
                            f : "Unmanned spacecraft",
                            g : "Land-based remote-sensing device",
                            h : "Water surface-based remote-sensing device",
                            i : "Submersible remote-sensing device",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Platform use category",
                    values: {    a : "Meteorological",
                            b : "Surface observing",
                            c : "Space observing",
                            m : "Mixed uses",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 8,
                    len   : 1,
                    label : "Sensor type",
                    values: {    a : "Active",
                            b : "Passive",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                j : {    start : 9,
                    len   : 2,
                    label : "Data type",
                    values: {    nn : "Not applicable",
                            uu : "Unknown",
                            zz : "Other",
                            aa : "Visible light",
                            da : "Near infrared",
                            db : "Middle infrared",
                            dc : "Far infrared",
                            dd : "Thermal infrared",
                            de : "Shortwave infrared (SWIR)",
                            df : "Reflective infrared",
                            dv : "Combinations",
                            dz : "Other infrared data",
                            ga : "Sidelooking airborne radar (SLAR)",
                            gb : "Synthetic aperture radar (SAR-single frequency)",
                            gc : "SAR-multi-frequency (multichannel)",
                            gd : "SAR-like polarization",
                            ge : "SAR-cross polarization",
                            gf : "Infometric SAR",
                            gg : "Polarmetric SAR",
                            gu : "Passive microwave mapping",
                            gz : "Other microwave data",
                            ja : "Far ultraviolet",
                            jb : "Middle ultraviolet",
                            jc : "Near ultraviolet",
                            jv : "Ultraviolet combinations",
                            jz : "Other ultraviolet data",
                            ma : "Multi-spectral, multidata",
                            mb : "Multi-temporal",
                            mm : "Combination of various data types",
                            pa : "Sonar-water depth",
                            pb : "Sonar-bottom topography images, sidescan",
                            pc : "Sonar-bottom topography, near-surface",
                            pd : "Sonar-bottom topography, near-bottom",
                            pe : "Seismic surveys",
                            pz : "Other acoustical data",
                            ra : "Gravity anomales (general)",
                            rb : "Free-air",
                            rc : "Bouger",
                            rd : "Isostatic",
                            sa : "Magnetic field",
                            ta : "Radiometric surveys"
                    }
                }
            }
        },
        s : {
            label     : "Sound Recording",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    d : "Sound disc",
                            e : "Cylinder",
                            g : "Sound cartridge",
                            i : "Sound-track film",
                            q : "Roll",
                            s : "Sound cassette",
                            t : "Sound-tape reel",
                            u : "Unspecified",
                            w : "Wire recording",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Speed",
                    values: {    a : "16 rpm",
                            b : "33 1/3 rpm",
                            c : "45 rpm",
                            d : "78 rpm",
                            e : "8 rpm",
                            f : "1.4 mps",
                            h : "120 rpm",
                            i : "160 rpm",
                            k : "15/16 ips",
                            l : "1 7/8 ips",
                            m : "3 3/4 ips",
                            o : "7 1/2 ips",
                            p : "15 ips",
                            r : "30 ips",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Configuration of playback channels",
                    values: {    m : "Monaural",
                            q : "Quadraphonic",
                            s : "Stereophonic",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Groove width or pitch",
                    values: {    m : "Microgroove/fine",
                            n : "Not applicable",
                            s : "Coarse/standard",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "3 in.",
                            b : "5 in.",
                            c : "7 in.",
                            d : "10 in.",
                            e : "12 in.",
                            f : "16 in.",
                            g : "4 3/4 in. (12 cm.)",
                            j : "3 7/8 x 2 1/2 in.",
                            o : "5 1/4 x 3 7/8 in.",
                            s : "2 3/4 x 4 in.",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Tape width",
                    values: {    l : "1/8 in.",
                            m : "1/4in.",
                            n : "Not applicable",
                            o : "1/2 in.",
                            p : "1 in.",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 8,
                    len   : 1,
                    label : "Tape configuration ",
                    values: {    a : "Full (1) track",
                            b : "Half (2) track",
                            c : "Quarter (4) track",
                            d : "8 track",
                            e : "12 track",
                            f : "16 track",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                m : {    start : 12,
                    len   : 1,
                    label : "Special playback",
                    values: {    a : "NAB standard",
                            b : "CCIR standard",
                            c : "Dolby-B encoded, standard Dolby",
                            d : "dbx encoded",
                            e : "Digital recording",
                            f : "Dolby-A encoded",
                            g : "Dolby-C encoded",
                            h : "CX encoded",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                n : {    start : 13,
                    len   : 1,
                    label : "Capture and storage",
                    values: {    a : "Acoustical capture, direct storage",
                            b : "Direct storage, not acoustical",
                            d : "Digital storage",
                            e : "Analog electrical storage",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        f : {
            label     : "Tactile Material",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {    a : "Moon",
                            b : "Braille",
                            c : "Combination",
                            d : "Tactile, with no writing system",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 2,
                    label : "Class of braille writing",
                    values: {    a : "Literary braille",
                            b : "Format code braille",
                            c : "Mathematics and scientific braille",
                            d : "Computer braille",
                            e : "Music braille",
                            m : "Multiple braille types",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Level of contraction",
                    values: {    a : "Uncontracted",
                            b : "Contracted",
                            m : "Combination",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                f : {    start : 6,
                    len   : 3,
                    label : "Braille music format",
                    values: {    a : "Bar over bar",
                            b : "Bar by bar",
                            c : "Line over line",
                            d : "Paragraph",
                            e : "Single line",
                            f : "Section by section",
                            g : "Line by line",
                            h : "Open score",
                            i : "Spanner short form scoring",
                            j : "Short form scoring",
                            k : "Outline",
                            l : "Vertical score",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                g : {    start : 9,
                    len   : 1,
                    label : "Special physical characteristics",
                    values: {    a : "Print/braille",
                            b : "Jumbo or enlarged braille",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        },
        v : {
            label     : "Videorecording",
            subfields : {
                b : {    start : 1,
                    len   : 1,
                    label : "SMD",
                    values: {     c : "Videocartridge",
                            d : "Videodisc",
                            f : "Videocassette",
                            r : "Videoreel",
                            u : "Unspecified",
                            z : "Other"
                    }
                },
                d : {    start : 3,
                    len   : 1,
                    label : "Color",
                    values: {    b : "Black-and-white",
                            c : "Multicolored",
                            m : "Mixed",
                            n : "Not applicable",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                e : {    start : 4,
                    len   : 1,
                    label : "Videorecording format",
                    values: {    a : "Beta",
                            b : "VHS",
                            c : "U-matic",
                            d : "EIAJ",
                            e : "Type C",
                            f : "Quadruplex",
                            g : "Laserdisc",
                            h : "CED",
                            i : "Betacam",
                            j : "Betacam SP",
                            k : "Super-VHS",
                            m : "M-II",
                            o : "D-2",
                            p : "8 mm.",
                            q : "Hi-8 mm.",
                            u : "Unknown",
                            v : "DVD",
                            z : "Other"
                    }
                },
                f : {    start : 5,
                    len   : 1,
                    label : "Sound on medium or separate",
                    values: {    a : "Sound on medium",
                            b : "Sound separate from medium",
                            u : "Unknown"
                    }
                },
                g : {    start : 6,
                    len   : 1,
                    label : "Medium for sound",
                    values: {    a : "Optical sound track on motion picture film",
                            b : "Magnetic sound track on motion picture film",
                            c : "Magnetic audio tape in cartridge",
                            d : "Sound disc",
                            e : "Magnetic audio tape on reel",
                            f : "Magnetic audio tape in cassette",
                            g : "Optical and magnetic sound track on motion picture film",
                            h : "Videotape",
                            i : "Videodisc",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                h : {    start : 7,
                    len   : 1,
                    label : "Dimensions",
                    values: {    a : "8 mm.",
                            m : "1/4 in.",
                            o : "1/2 in.",
                            p : "1 in.",
                            q : "2 in.",
                            r : "3/4 in.",
                            u : "Unknown",
                            z : "Other"
                    }
                },
                i : {    start : 8,
                    len   : 1,
                    label : "Configuration of playback channel",
                    values: {    k : "Mixed",
                            m : "Monaural",
                            n : "Not applicable",
                            q : "Multichannel, surround or quadraphonic",
                            s : "Stereophonic",
                            u : "Unknown",
                            z : "Other"
                    }
                }
            }
        }
    };
    
    MARC.Record.prototype.recordType = function () {
    
        var _t = this.leader.substr(MARC.Record._ff_pos.Type.ldr.BKS.start, MARC.Record._ff_pos.Type.ldr.BKS.len);
        var _b = this.leader.substr(MARC.Record._ff_pos.BLvl.ldr.BKS.start, MARC.Record._ff_pos.BLvl.ldr.BKS.len);
    
        for (var t in MARC.Record._recType) {
            if (_t.match(MARC.Record._recType[t].Type) && _b.match(MARC.Record._recType[t].BLvl)) {
                return t;
            }
        }
        return 'BKS'; // default
    }
    
    MARC.Record.prototype.videorecordingFormatName = function () {
        var _7 = this.field('007').data;
    
        if (_7 && _7.match(/^v/)) {
            var _v_e = _7.substr(
                MARC.Record._physical_characteristics.v.subfields.e.start,
                MARC.Record._physical_characteristics.v.subfields.e.len
            );
    
            return MARC.Record._physical_characteristics.v.subfields.e.values[ _v_e ];
        }
    
        return null;
    }
    
    MARC.Record.prototype.videorecordingFormatCode = function () {
        var _7 = this.field('007').data;
    
        if (_7 && _7.match(/^v/)) {
            return _7.substr(
                MARC.Record._physical_characteristics.v.subfields.e.start,
                MARC.Record._physical_characteristics.v.subfields.e.len
            );
        }
    
        return null;
    }
    
    MARC.Record.prototype.extractFixedField = function (field, dflt) {
    if (!MARC.Record._ff_pos[field]) return null;
    
        var _l = this.leader;
        var _8 = this.field('008').data;
        var _6 = this.field('006').data;
    
        var rtype = this.recordType();
    
        var val;
    
        if (MARC.Record._ff_pos[field].ldr && _l) {
            if (MARC.Record._ff_pos[field].ldr[rtype]) {
                val = _l.substr(
                    MARC.Record._ff_pos[field].ldr[rtype].start,
                    MARC.Record._ff_pos[field].ldr[rtype].len
                );
            }
        } else if (MARC.Record._ff_pos[field]._8 && _8) {
            if (MARC.Record._ff_pos[field]._8[rtype]) {
                val = _8.substr(
                    MARC.Record._ff_pos[field]._8[rtype].start,
                    MARC.Record._ff_pos[field]._8[rtype].len
                );
            }
        }
    
        if (!val && MARC.Record._ff_pos[field]._6 && _6) {
            if (MARC.Record._ff_pos[field]._6[rtype]) {
                val = _6.substr(
                    MARC.Record._ff_pos[field]._6[rtype].start,
                    MARC.Record._ff_pos[field]._6[rtype].len
                );
            }
        }

        if (!val && dflt) {
            val = '';
            var d;
            var p;
            if (MARC.Record._ff_pos[field].ldr && MARC.Record._ff_pos[field].ldr[rtype]) {
                d = MARC.Record._ff_pos[field].ldr[rtype].def;
                p = 'ldr';
            }

            if (MARC.Record._ff_pos[field]._8 && MARC.Record._ff_pos[field]._8[rtype]) {
                d = MARC.Record._ff_pos[field]._8[rtype].def;
                p = '_8';
            }

            if (!val && MARC.Record._ff_pos[field]._6 && MARC.Record._ff_pos[field]._6[rtype]) {
                d = MARC.Record._ff_pos[field]._6[rtype].def;
                p = '_6';
            }

            if (p) {
                for (var j = 0; j < MARC.Record._ff_pos[field][p][rtype].len; j++) {
                    val += d;
                }
            } else {
                val = null;
            }
        }

        return val;
    }

    MARC.Record.prototype.setFixedField = function (field, value) {
    if (!MARC.Record._ff_pos[field]) return null;
    
        var _l = this.leader;
        var _8 = this.field('008').data;
        var _6 = this.field('006').data;
    
        var rtype = this.recordType();
    
        var val;
    
        if (MARC.Record._ff_pos[field].ldr && _l) {
            if (MARC.Record._ff_pos[field].ldr[rtype]) { // It's in the leader
                val = value.substr(0, MARC.Record._ff_pos[field].ldr[rtype].len);
                if (val.length < MARC.Record._ff_pos[field].ldr[rtype].len) {
                    //right-pad val with the appropriate default character
                    val += Array(MARC.Record._ff_pos[field].ldr[rtype].len - val.length + 1).join(MARC.Record._ff_pos[field].ldr[rtype].def);
                }
                this.leader =
                    _l.substring(0, MARC.Record._ff_pos[field].ldr[rtype].start) +
                    val +
                    _l.substring(
                        MARC.Record._ff_pos[field].ldr[rtype].start
                        + MARC.Record._ff_pos[field].ldr[rtype].len
                    );
            }
        } else if (MARC.Record._ff_pos[field]._8 && _8) {
            if (MARC.Record._ff_pos[field]._8[rtype]) { // Nope, it's in the 008
                val = value.substr(0, MARC.Record._ff_pos[field]._8[rtype].len);
                if (val.length < MARC.Record._ff_pos[field]._8[rtype].len) {
                    //right-pad val with the appropriate default character
                    val += Array(MARC.Record._ff_pos[field]._8[rtype].len - val.length + 1).join(MARC.Record._ff_pos[field]._8[rtype].def);
                }
                this.field('008').update(
                    _8.substring(0, MARC.Record._ff_pos[field]._8[rtype].start) +
                    val +
                    _8.substring(
                        MARC.Record._ff_pos[field]._8[rtype].start
                        + MARC.Record._ff_pos[field]._8[rtype].len
                    )
                );
            }
        }
    
        if (!val && MARC.Record._ff_pos[field]._6 && _6) {
            if (MARC.Record._ff_pos[field]._6[rtype]) { // ok, maybe the 006?
                val = value.substr(0, MARC.Record._ff_pos[field]._6[rtype].len);
                if (val.length < MARC.Record._ff_pos[field]._6[rtype].len) {
                    //right-pad val with the appropriate default character
                    val += Array(MARC.Record._ff_pos[field]._6[rtype].len - val.length + 1).join(MARC.Record._ff_pos[field]._6[rtype].def);
                }
                this.field('006').update(
                    _6.substring(0, MARC.Record._ff_pos[field]._6[rtype].start) +
                    val +
                    _6.substring(
                        MARC.Record._ff_pos[field]._6[rtype].start
                        + MARC.Record._ff_pos[field]._6[rtype].len
                    )
                );
            }
        }

        return val;
    }
} 

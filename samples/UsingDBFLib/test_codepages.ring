/*
**  test_codepages.ring
**  ===========================================================
**
**  Creates one DBF file per codepage constant.
**  Each file is named:  cp_<hex>_<name>.dbf
**  e.g.  cp_03_WIN1252.dbf
**
**  Codepage byte values sourced from Microsoft VFP9 CPZERO.PRG.
**
**  Open every generated file in VFP9.  A file that opens
**  silently (no dialog) means its byte[29] value is correct.
**  ===========================================================
*/

load "dbflib.ring"

func main

    aCodePages = [
        # No codepage marker
        [ C_CODEPAGE_NONE,      "NONE"      ],   # 0x00 — expected to show dialog (correct behaviour)

        # MS-DOS codepages
        [ C_CODEPAGE_DOS_437,   "DOS437"    ],   # 0x01
        [ C_CODEPAGE_DOS_850,   "DOS850"    ],   # 0x02
        [ C_CODEPAGE_DOS_852,   "DOS852"    ],   # 0x64
        [ C_CODEPAGE_DOS_865,   "DOS865"    ],   # 0x66
        [ C_CODEPAGE_DOS_866,   "DOS866"    ],   # 0x65
        [ C_CODEPAGE_DOS_861,   "DOS861"    ],   # 0x67
        [ C_CODEPAGE_DOS_857,   "DOS857"    ],   # 0x6B
        [ C_CODEPAGE_DOS_737,   "DOS737"    ],   # 0x6A
        [ C_CODEPAGE_DOS_863,   "DOS863"    ],   # 0x6C

        # Macintosh codepages
        [ C_CODEPAGE_MAC_ROMAN, "MACROMAN"  ],   # 0x04

        # Windows codepages
        [ C_CODEPAGE_WIN_1252,  "WIN1252"   ],   # 0x03
        [ C_CODEPAGE_WIN_874,   "WIN874"    ],   # 0x7C
        [ C_CODEPAGE_WIN_1250,  "WIN1250"   ],   # 0xC8
        [ C_CODEPAGE_WIN_1251,  "WIN1251"   ],   # 0xC9
        [ C_CODEPAGE_WIN_1253,  "WIN1253"   ],   # 0xCB
        [ C_CODEPAGE_WIN_1254,  "WIN1254"   ],   # 0xCA
        [ C_CODEPAGE_WIN_1255,  "WIN1255"   ],   # 0x7D
        [ C_CODEPAGE_WIN_1256,  "WIN1256"   ],   # 0x7E  confirmed
        [ C_CODEPAGE_WIN_1257,  "WIN1257"   ]    # 0xCC  confirmed
    ]

    ? "================================================"
    ? "  dbflib Codepage Verification"
    ? "================================================"
    ? ""

    nTotal = len(aCodePages)
    for i = 1 to nTotal

        nCpValue = aCodePages[i][1]
        cCpName  = aCodePages[i][2]

        # Build filename:  cp_<hex>_<name>.dbf  (hex zero-padded to 2 digits)
        cHex      = right("0" + hex(nCpValue), 2)
        cFileName = "cp_" + cHex + "_" + cCpName + ".dbf"

        # Create the DBF
        oDbf = new DBFFile
        oDbf.create(cFileName, [
            ["ID",    "N",  4, 0],
            ["LABEL", "C", 30, 0]
        ])

        # Write one record so VFP9 has something to display
        oDbf.append()
        oDbf.replace("ID",    i)
        oDbf.replace("LABEL", cCpName + " codepage test")

        # Stamp the codepage byte
        oDbf.setCodePage(nCpValue)

        oDbf.close()

        ? "  Created: " + cFileName + "  (byte[29] = 0x" + cHex + ")"

    next

    ? ""
    ? "------------------------------------------------"
    ? "  " + nTotal + " files created."
    ? ""
    ? "  Instructions:"
    ? "  1. Open each file in VFP9."
    ? "  2. Files that open silently = byte value is correct."
    ? "  3. Files that show 'Select Code Page' dialog = wrong."
    ? "  Note: cp_00_NONE.dbf is expected to show the dialog"
    ? "        (0x00 = no codepage marked) — this is correct"
    ? "        behaviour for C_CODEPAGE_NONE."
    ? "------------------------------------------------"

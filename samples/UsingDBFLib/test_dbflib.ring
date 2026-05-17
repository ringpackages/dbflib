/*
**  test_dbflib.ring
**  Test Suite for Ring DBF Library
*/

load "dbflib.ring"

# ===============================================================
# Counters
# ===============================================================

nTestPass = 0
nTestFail = 0

func main

    # ===============================================================
    # Test 1: Create a New DBF File
    # ===============================================================

    ? "=============================================="
    ? "  Ring DBF Library - Test Suite"
    ? "=============================================="
    ? ""
    ? "--- Test 1: Create a new DBF file ---"

    oDbf = new DBFFile   # Rule 3: no () — no init() defined

    aStructure = [
        ["ID",       "N",  6, 0],
        ["NAME",     "C", 30, 0],
        ["CITY",     "C", 20, 0],
        ["SALARY",   "N", 12, 2],
        ["HIREDATE", "D",  8, 0],
        ["ACTIVE",   "L",  1, 0],
        ["NOTES",    "M", 10, 0]
    ]

    lOk = oDbf.create("test_employees.dbf", aStructure)
    assert(lOk,                        "File created successfully")
    assert(oDbf.fieldCount() = 7,      "Field count = 7")
    assert(oDbf.recCount() = 0,        "New file has 0 records")

    # ===============================================================
    # Test 2: Code Page Methods
    # ===============================================================

    ? ""
    ? "--- Test 2: Code Page Methods ---"

    assert(oDbf.getCodePage() = C_CODEPAGE_WIN_1252,         "Default code page is WIN_1252")

    oDbf.setCodePage(C_CODEPAGE_WIN_1256)
    assert(oDbf.getCodePage() = C_CODEPAGE_WIN_1256,         "setCodePage(WIN_1256) works")
    assert(oDbf.getCodePageName() = "Windows Arabic (CP 1256)", "getCodePageName() for WIN_1256")

    oDbf.setCodePage(C_CODEPAGE_WIN_1252)
    assert(oDbf.getCodePage() = C_CODEPAGE_WIN_1252,         "setCodePage back to WIN_1252")

    # ===============================================================
    # Test 3: File Info
    # ===============================================================

    ? ""
    ? "--- Test 3: File Structure Info ---"

    cInfo = oDbf.info()
    assert(len(cInfo) > 50,              "info() returns non-trivial string")
    assert(substr(cInfo, "Records") > 0, "info() mentions Records")
    assert(substr(cInfo, "SALARY")  > 0, "info() lists SALARY field")

    # ===============================================================
    # Test 4: Append Records
    # ===============================================================

    ? ""
    ? "--- Test 4: Append Records ---"

    aEmployees = [
        [1,  "Ahmed Al-Rashid",   "Riyadh", 85000.50, "20230115", true,  "Senior developer"],
        [2,  "Fatima Hassan",     "Jeddah", 72000.00, "20220610", true,  "Team lead"],
        [3,  "Mohammed Khalil",   "Dammam", 65500.75, "20240301", true,  "Junior developer"],
        [4,  "Sara Abdullah",     "Riyadh", 91000.00, "20210520", true,  "Project manager"],
        [5,  "Omar bin Said",     "Medina", 58000.25, "20230815", false, "Contractor"],
        [6,  "Noura Al-Qahtani", "Riyadh", 77500.00, "20220101", true,  "Senior analyst"],
        [7,  "Khalid Mansour",   "Jeddah", 69000.00, "20240715", true,  "Developer"],
        [8,  "Aisha bint Faisal","Dammam", 83000.50, "20200901", true,  "Tech lead"],
        [9,  "Yousef Al-Amri",   "Riyadh", 55000.00, "20241001", false, "Intern promoted"],
        [10, "Layla Othman",      "Tabuk",  62000.75, "20230401", true,  "QA engineer"]
    ]

    # Rule 6: cache len() before the loop
    nEmpCount = len(aEmployees)
    for x = 1 to nEmpCount
        aEmp = aEmployees[x]
        oDbf.append()
        oDbf.replace("ID",       aEmp[1])
        oDbf.replace("NAME",     aEmp[2])
        oDbf.replace("CITY",     aEmp[3])
        oDbf.replace("SALARY",   aEmp[4])
        oDbf.replace("HIREDATE", aEmp[5])
        oDbf.replace("ACTIVE",   aEmp[6])
        oDbf.replace("NOTES",    aEmp[7])
    next

    assert(oDbf.recCount() = 10, "Record count = 10 after inserts")

    # ===============================================================
    # Test 5: Navigate & Read
    # ===============================================================

    ? ""
    ? "--- Test 5: Navigate and Read Records ---"

    oDbf.goTop()
    assert(oDbf.recNo() = 1,                               "goTop() lands on record 1")
    assert(oDbf.isBof(),                                   "isBof() true at record 1")
    assert(!oDbf.isEof(),                                  "isEof() false at record 1")
    assert(trim(oDbf.fieldGet("NAME")) = "Ahmed Al-Rashid","Record 1 name correct")
    assert(trim(oDbf.fieldGet("CITY")) = "Riyadh",         "Record 1 city correct")
    assert(oDbf.fieldGet("NOTES") = "Senior developer",    "Record 1 memo via fieldGet() correct")

    oDbf.goBottom()
    assert(oDbf.recNo() = 10,  "goBottom() lands on record 10")
    assert(!oDbf.isBof(),      "isBof() false at record 10")

    oDbf.goTo(5)
    assert(oDbf.recNo() = 5,                               "goTo(5) lands on record 5")
    assert(trim(oDbf.fieldGet("NAME")) = "Omar bin Said",  "Record 5 name correct")
    assert(oDbf.fieldGet("ACTIVE") = false,                "Record 5 ACTIVE = false")

    # ===============================================================
    # Test 6: skip() and EOF/BOF
    # ===============================================================

    ? ""
    ? "--- Test 6: skip() and EOF/BOF ---"

    oDbf.goTop()
    oDbf.skip(-1)
    assert(oDbf.isBof(), "skip(-1) from top sets BOF")

    oDbf.goBottom()
    oDbf.skip(1)
    assert(oDbf.isEof(), "skip(1) from bottom sets EOF")

    oDbf.goTo(3)
    oDbf.skip(2)
    assert(oDbf.recNo() = 5, "skip(2) from record 3 lands on 5")

    # ===============================================================
    # Test 7: Sequential Read
    # ===============================================================

    ? ""
    ? "--- Test 7: Sequential read (all records) ---"

    oDbf.goTop()
    nCount = 0
    while ! oDbf.isEof()
        nCount++
        oDbf.skip(1)
    end
    assert(nCount = 10, "Sequential scan visits all 10 records")

    # ===============================================================
    # Test 8: locate() always searches from record 1
    # ===============================================================

    ? ""
    ? "--- Test 8: locate() always searches from record 1 ---"

    oDbf.goBottom()   # position at end first to prove locate() resets
    lFound = oDbf.locate("CITY", "Riyadh")
    assert(lFound,                                                "locate() finds Riyadh from any position")
    assert(oDbf.recNo() = 1,                                     "locate() finds FIRST Riyadh (rec 1)")
    assert(trim(oDbf.fieldGet("NAME")) = "Ahmed Al-Rashid",      "First Riyadh is Ahmed Al-Rashid")

    lFound2 = oDbf.locateNext("CITY", "Riyadh")
    assert(lFound2,             "locateNext() finds second Riyadh record")
    assert(oDbf.recNo() > 1,   "locateNext() advanced past record 1")

    # Count all Riyadh records (should be 4: rec 1, 4, 6, 9)
    nRiyadh = 0
    if oDbf.locate("CITY", "Riyadh")
        nRiyadh++
        while oDbf.locateNext("CITY", "Riyadh")
            nRiyadh++
        end
    ok
    assert(nRiyadh = 4, "Exactly 4 Riyadh records")

    # ===============================================================
    # Test 9: Update a Record
    # ===============================================================

    ? ""
    ? "--- Test 9: Update Record ---"

    oDbf.goTo(3)
    oDbf.replace("SALARY", 70000.00)
    assert(trim(oDbf.fieldGet("SALARY")) = "70000.00", "Record 3 salary updated to 70000.00")

    # ===============================================================
    # Test 10: Delete & Recall
    # ===============================================================

    ? ""
    ? "--- Test 10: Delete and Recall ---"

    oDbf.goTo(5)
    assert(!oDbf.isDeleted(), "Record 5 not deleted before deleteRec()")

    oDbf.deleteRec()
    assert(oDbf.isDeleted(),  "Record 5 deleted after deleteRec()")

    oDbf.recall()
    assert(!oDbf.isDeleted(), "Record 5 undeleted after recall()")

    # ===============================================================
    # Test 11: Export to List
    # ===============================================================

    ? ""
    ? "--- Test 11: Export to List ---"

    aAll = oDbf.toList()
    assert(len(aAll) = 10,     "toList() exports all 10 non-deleted records")
    assert(len(aAll[1]) = 7,   "Each row has 7 fields")

    # ===============================================================
    # Test 12: toMapList()
    # ===============================================================

    ? ""
    ? "--- Test 12: toMapList() ---"

    aMap = oDbf.toMapList()
    assert(len(aMap) = 10,         "toMapList() exports 10 records")
    assert(len(aMap[1]) = 7,       "Each map row has 7 pairs")
    assert(aMap[1][1][1] = "ID",   "First pair key is ID")    # Rule 4: [1][1] = first pair, first element
    assert(aMap[1][2][1] = "NAME", "Second pair key is NAME") # Rule 4: [1][2][1]

    # ===============================================================
    # Test 13: Memo fields readable via fieldGet()
    # ===============================================================

    ? ""
    ? "--- Test 13: Memo fields via fieldGet() ---"

    oDbf.goTop()
    nMemoCount = 0
    while ! oDbf.isEof()
        cNotes = oDbf.fieldGet("NOTES")
        if len(cNotes) > 0
            nMemoCount++
        ok
        oDbf.skip(1)
    end
    assert(nMemoCount = 10, "All 10 records have non-empty memos via fieldGet()")

    # ===============================================================
    # Test 14: replace() and fieldGet() work transparently on memo fields
    # ===============================================================

    ? ""
    ? "--- Test 14: replace()/fieldGet() transparent on memo fields ---"

    oDbf.goTo(1)
    oDbf.replace("NOTES", "Updated via replace()")
    assert(oDbf.fieldGet("NOTES") = "Updated via replace()",
           "replace() writes memo and fieldGet() reads it back correctly")

    # memoRead() and memoWrite() still work as explicit aliases
    oDbf.memoWrite("NOTES", "Senior developer")   # restore original value
    assert(oDbf.memoRead("NOTES") = "Senior developer",
           "memoRead()/memoWrite() still work as explicit aliases")

    # ===============================================================
    # Test 15: Numeric overflow raises
    # ===============================================================

    ? ""
    ? "--- Test 15: Numeric overflow detection ---"

    oDbf.goTo(1)
    lRaised = false
    try
        # ID field is 6 chars wide; 9999999 is 7 chars
        oDbf.replace("ID", 9999999)
    catch
        lRaised = true
    done
    assert(lRaised, "Overflow on N field correctly raises an error")

    # ===============================================================
    # Test 16: Field Info Access
    # ===============================================================

    ? ""
    ? "--- Test 16: Field Information ---"

    assert(oDbf.fieldName(1) = "ID",    "Field 1 name is ID")
    assert(oDbf.fieldType(1) = "N",     "Field 1 type is N")
    assert(oDbf.fieldLen(1)  = 6,       "Field 1 length is 6")
    assert(oDbf.fieldDec(1)  = 0,       "Field 1 decimals is 0")
    assert(oDbf.fieldName(2) = "NAME",  "Field 2 name is NAME")
    assert(oDbf.fieldType(2) = "C",     "Field 2 type is C")
    assert(oDbf.fieldLen(2)  = 30,      "Field 2 length is 30")
    assert(oDbf.fieldName(7) = "NOTES", "Field 7 name is NOTES")
    assert(oDbf.fieldType(7) = "M",     "Field 7 type is M")

    # ===============================================================
    # Test 17: Delete + Pack
    # ===============================================================

    ? ""
    ? "--- Test 17: Delete records and pack ---"

    oDbf.goTo(2)
    oDbf.deleteRec()
    oDbf.goTo(7)
    oDbf.deleteRec()
    oDbf.pack()
    assert(oDbf.recCount() = 8, "After deleting 2 and packing, 8 records remain")

    oDbf.goTop()
    assert(trim(oDbf.fieldGet("NAME")) = "Ahmed Al-Rashid",
           "After pack record 1 is Ahmed Al-Rashid")

    # ===============================================================
    # Close main test file before Test 17b
    # ===============================================================

    ? ""
    ? "--- Closing files ---"
    oDbf.close()
    ? "  [OK] Files closed"

    # ===============================================================
    # Test 17b: packFpt() standalone — FPT compaction without deleting records
    #
    # Uses its OWN separate file (test_packfpt.dbf / .fpt) so that
    # test_employees.dbf is never altered and Tests 18-21 can verify
    # the original data without any workarounds.
    #
    # Strategy:
    #   (a) Create a fresh 3-record DBF with a memo field.
    #   (b) Overwrite each memo twice to accumulate orphaned FPT blocks.
    #   (c) Call packFpt() directly (standalone, no record deletion).
    #   (d) Verify every memo still reads back correctly.
    #   (e) Verify nFptNextBlock is compact (much less than 3x records).
    # ===============================================================

    ? ""
    ? "--- Test 17b: packFpt() standalone compaction ---"

    oFpt = new DBFFile
    oFpt.create("test_packfpt.dbf", [
        ["ID",    "N",  4, 0],
        ["LABEL", "C", 20, 0],
        ["NOTES", "M", 10, 0]
    ])

    # Insert 3 records with initial memo text using replace() transparently
    nFptRecs = 3
    for i = 1 to nFptRecs
        oFpt.append()
        oFpt.replace("ID",    i)
        oFpt.replace("LABEL", "Record " + i)
        oFpt.replace("NOTES", "original memo " + i)
    next

    # Overwrite every memo twice — creates 2 orphaned blocks per record
    oFpt.goTop()
    while ! oFpt.isEof()
        oFpt.replace("NOTES", "overwrite A rec " + oFpt.recNo())
        oFpt.skip(1)
    end
    oFpt.goTop()
    while ! oFpt.isEof()
        oFpt.replace("NOTES", "final memo rec " + oFpt.recNo())
        oFpt.skip(1)
    end

    # Record the bloated next-block value before compaction
    nFptBefore = oFpt.nFptNextBlock

    # Compact the FPT — no records deleted
    oFpt.packFpt()

    nFptAfter = oFpt.nFptNextBlock

    # Verify every memo is intact
    oFpt.goTop()
    nBadMemo = 0
    nRecIdx  = 0
    while ! oFpt.isEof()
        nRecIdx++
        cExpected = "final memo rec " + oFpt.recNo()
        cActual   = oFpt.fieldGet("NOTES")
        if cActual != cExpected
            nBadMemo++
        ok
        oFpt.skip(1)
    end
    assert(nBadMemo = 0,           "All " + nRecIdx + " memos intact after packFpt()")
    assert(nFptAfter < nFptBefore, "FPT nNextBlock reduced by packFpt() (" +
                                    nFptBefore + " -> " + nFptAfter + ")")

    oFpt.close()

    # ===============================================================
    # Test 18: Reopen & Verify
    # ===============================================================

    ? ""
    ? "--- Test 18: Reopen and Verify Data ---"

    oDbf2 = new DBFFile
    oDbf2.open("test_employees.dbf")
    assert(oDbf2.recCount() = 8,                               "Reopened file has 8 records")
    assert(oDbf2.getCodePageName() = "Windows ANSI (CP 1252)", "Code page preserved across close/open")

    oDbf2.goTop()
    assert(trim(oDbf2.fieldGet("NAME")) = "Ahmed Al-Rashid",   "First record name correct after reopen")
    assert(oDbf2.fieldGet("NOTES") = "Senior developer",       "First record memo correct after reopen")

    oDbf2.goBottom()
    assert(oDbf2.recNo() = 8, "goBottom() lands on record 8 after pack")
    oDbf2.close()

    # ===============================================================
    # Test 19: Read-only open
    # ===============================================================

    ? ""
    ? "--- Test 19: Read-only field access ---"

    oDbf3 = new DBFFile
    oDbf3.open("test_employees.dbf")
    assert(oDbf3.recCount() = 8, "Reopened file sees correct record count")
    oDbf3.goTo(1)
    assert(trim(oDbf3.fieldGet("CITY")) = "Riyadh", "City field readable after reopen")
    oDbf3.close()

    # ===============================================================
    # Test 20: copyStructure
    # ===============================================================

    ? ""
    ? "--- Test 20: copyStructure ---"

    oDbf4 = new DBFFile
    oDbf4.open("test_employees.dbf")
    lCopied = oDbf4.copyStructure("test_copy.dbf")
    oDbf4.close()

    oDbf5 = new DBFFile
    oDbf5.open("test_copy.dbf")
    assert(oDbf5.fieldCount() = 7,     "Copied structure has 7 fields")
    assert(oDbf5.recCount()   = 0,     "Copied structure has 0 records")
    assert(oDbf5.fieldName(1) = "ID",  "Copied structure field 1 = ID")
    assert(oDbf5.fieldType(4) = "N",   "Copied structure field 4 type = N")
    oDbf5.close()

    # ===============================================================
    # Test 21: Code page constant values
    # ===============================================================

    ? ""
    ? "--- Test 21: Code page constant spot-check ---"

    assert(C_CODEPAGE_WIN_1252 = 0x03, "WIN_1252 = 0x03")
    assert(C_CODEPAGE_WIN_1256 = 0x7D, "WIN_1256 = 0x7D")
    assert(C_CODEPAGE_WIN_1251 = 0x79, "WIN_1251 = 0x79")
    assert(C_CODEPAGE_DOS_437  = 0x01, "DOS_437  = 0x01")
    assert(C_CODEPAGE_DOS_866  = 0x67, "DOS_866  = 0x67")

    # ===============================================================
    # Summary  (still a top-level statement — correct)
    # ===============================================================

    ? ""
    ? "=============================================="
    ? "  Test Results"
    ? "=============================================="
    ? "  Passed : " + nTestPass
    ? "  Failed : " + nTestFail
    ? "  Total  : " + (nTestPass + nTestFail)
    ? ""

    if nTestFail = 0
        ? "  ALL TESTS PASSED"
    else
        ? "  ** " + nTestFail + " TEST(S) FAILED **"
    ok

    ? "=============================================="

# ===============================================================
# Helper functions
# ===============================================================

func assert pCond, pMsg
    if pCond
        nTestPass++
        ? "  [PASS] " + pMsg
    else
        nTestFail++
        ? "  [FAIL] " + pMsg
    ok

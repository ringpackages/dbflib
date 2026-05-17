/*
**  test_performance.ring
**  Performance Test for Ring DBF Library
*/

load "dbflib.ring"

func main

    Decimals(3)

    ? "=============================================="
    ? "  DBF Library Performance Test"
    ? "  Testing with 10,000 records"
    ? "=============================================="
    ? ""

    # ---------------------------------------------------------------
    # Data tables for random-ish generation
    # Rule 6: lengths cached once, used throughout
    # ---------------------------------------------------------------
    aFirstNames = ["Ahmed",  "Mohammed", "Ali",    "Omar",   "Khalid",
                   "Yousef", "Hassan",   "Ibrahim","Saad",   "Faisal",
                   "Fatima", "Aisha",    "Noura",  "Sara",   "Layla",
                   "Maha",   "Huda",     "Reem",   "Dana",   "Lina"]

    aLastNames  = ["Al-Rashid",  "Al-Qahtani", "Al-Dosari",  "Al-Harbi",
                   "Al-Mutairi", "Al-Otaibi",  "Al-Zahrani", "Al-Ghamdi",
                   "Al-Shehri",  "Al-Malki",   "Hassan",     "Abdullah",
                   "Mansour",    "Khalil",     "Othman"]

    aCities     = ["Riyadh", "Jeddah",  "Dammam",  "Mecca",   "Medina",
                   "Khobar",  "Tabuk",   "Abha",    "Taif",    "Buraidah"]

    aDepartments = ["IT",         "HR",      "Finance", "Sales",  "Marketing",
                    "Operations", "Legal",   "R&D",     "Support","Admin"]

    aPositions  = ["Manager",     "Senior Developer", "Developer", "Analyst",
                   "Specialist",  "Coordinator",      "Director",  "Engineer",
                   "Consultant",  "Associate"]

    # Rule 6: cache all list lengths before any loop
    nFirstCount = len(aFirstNames)
    nLastCount  = len(aLastNames)
    nCityCount  = len(aCities)
    nDeptCount  = len(aDepartments)
    nPosCount   = len(aPositions)

    # ---------------------------------------------------------------
    # Step 1: Create DBF Structure
    # ---------------------------------------------------------------

    ? "--- Step 1: Creating DBF file structure ---"

    nStart = clock()

    oDbf = new DBFFile   # Rule 3: no ()

    # SALARY widened to 14,2 so the 5% raise in step 7 never triggers overflow
    aStructure = [
        ["ID",         "N",  8, 0],
        ["FIRSTNAME",  "C", 20, 0],
        ["LASTNAME",   "C", 25, 0],
        ["CITY",       "C", 15, 0],
        ["DEPARTMENT", "C", 15, 0],
        ["POSITION",   "C", 20, 0],
        ["SALARY",     "N", 14, 2],
        ["HIREDATE",   "D",  8, 0],
        ["ACTIVE",     "L",  1, 0],
        ["NOTES",      "M", 10, 0]
    ]

    oDbf.create("performance_test.dbf", aStructure)

    nEnd = clock()
    ? "  Created in " + ((nEnd - nStart) / clockspersecond()) + " seconds"

    # ---------------------------------------------------------------
    # Step 2: Insert 10,000 Records
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 2: Inserting 10,000 records ---"

    nStart   = clock()
    nRecords = 10000

    for i = 1 to nRecords

        # Pseudo-random selection using modulo (Rule 6: lengths cached above)
        nFirstIdx = (i % nFirstCount) + 1
        nLastIdx  = (i % nLastCount)  + 1
        nCityIdx  = (i % nCityCount)  + 1
        nDeptIdx  = (i % nDeptCount)  + 1
        nPosIdx   = (i % nPosCount)   + 1

        cFirstName = aFirstNames[nFirstIdx]
        cLastName  = aLastNames[nLastIdx]
        cCity      = aCities[nCityIdx]
        cDept      = aDepartments[nDeptIdx]
        cPos       = aPositions[nPosIdx]

        nSalary = 30000 + (i % 70000) + ((i % 100) / 100)

        nYear  = 2015 + (i % 10)
        nMonth = (i % 12) + 1
        nDay   = (i % 28) + 1
        cDate  = "" + nYear
        if nMonth < 10 cDate += "0" ok
        cDate += "" + nMonth
        if nDay < 10 cDate += "0" ok
        cDate += "" + nDay

        lActive = (i % 5) != 0    # 80% active

        cNotes = cPos + " in " + cDept + " department"

        oDbf.append()
        oDbf.replace("ID",         i)
        oDbf.replace("FIRSTNAME",  cFirstName)
        oDbf.replace("LASTNAME",   cLastName)
        oDbf.replace("CITY",       cCity)
        oDbf.replace("DEPARTMENT", cDept)
        oDbf.replace("POSITION",   cPos)
        oDbf.replace("SALARY",     nSalary)
        oDbf.replace("HIREDATE",   cDate)
        oDbf.replace("ACTIVE",     lActive)
        oDbf.replace("NOTES",       cNotes)

        if i % 1000 = 0
            ? "  Inserted " + i + " records..."
        ok

    next

    nEnd        = clock()
    nInsertTime = (nEnd - nStart) / clockspersecond()
    ? "  Inserted " + nRecords + " records in " + nInsertTime + " seconds"
    ? "  Rate: " + floor(nRecords / nInsertTime) + " records/second"

    # ---------------------------------------------------------------
    # Step 3: Close and Reopen
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 3: Close and reopen file ---"

    nStart = clock()
    oDbf.close()
    nEnd = clock()
    ? "  Closed in " + ((nEnd - nStart) / clockspersecond()) + " seconds"

    nStart = clock()
    oDbf   = new DBFFile
    oDbf.open("performance_test.dbf")
    nEnd   = clock()
    ? "  Reopened in " + ((nEnd - nStart) / clockspersecond()) + " seconds"
    ? "  Record count: " + oDbf.recCount()

    # ---------------------------------------------------------------
    # Step 4: Sequential Read
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 4: Sequential read (all records) ---"

    nStart       = clock()
    nCount       = 0
    nTotalSalary = 0

    oDbf.goTop()
    while !oDbf.isEof()
        cName  = oDbf.fieldGet("FIRSTNAME")
        cCity  = oDbf.fieldGet("CITY")
        nSal   = number(oDbf.fieldGet("SALARY"))
        nTotalSalary += nSal
        nCount++
        oDbf.skip(1)
    end

    nEnd      = clock()
    nReadTime = (nEnd - nStart) / clockspersecond()
    ? "  Read " + nCount + " records in " + nReadTime + " seconds"
    ? "  Rate: " + floor(nCount / nReadTime) + " records/second"
    ? "  Average salary: " + floor(nTotalSalary / nCount)

    # ---------------------------------------------------------------
    # Step 5: Random Access
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 5: Random access (1,000 reads) ---"

    nStart = clock()
    nReads = 1000

    for i = 1 to nReads
        nRec  = (i * 7) % nRecords + 1
        oDbf.goTo(nRec)
        cName = oDbf.fieldGet("FIRSTNAME") + " " + oDbf.fieldGet("LASTNAME")
    next

    nEnd        = clock()
    nRandomTime = (nEnd - nStart) / clockspersecond()
    ? "  " + nReads + " random reads in " + nRandomTime + " seconds"
    ? "  Rate: " + floor(nReads / nRandomTime) + " reads/second"

    # ---------------------------------------------------------------
    # Step 6: Search / Locate
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 6: Search operations (locate / locateNext) ---"

    nStart = clock()
    nFound = 0

    # locate() always starts from record 1; locateNext() continues forward
    if oDbf.locate("CITY", "Riyadh")
        nFound++
        while oDbf.locateNext("CITY", "Riyadh")
            nFound++
        end
    ok

    nEnd        = clock()
    nSearchTime = (nEnd - nStart) / clockspersecond()
    ? "  Found " + nFound + " 'Riyadh' records in " + nSearchTime + " seconds"

    # ---------------------------------------------------------------
    # Step 7: Update 1,000 Records (5% salary raise)
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 7: Update 1,000 records (5% salary raise) ---"

    nStart   = clock()
    nUpdates = 1000

    for i = 1 to nUpdates
        nRec       = (i * 3) % nRecords + 1
        oDbf.goTo(nRec)
        nOldSalary = number(oDbf.fieldGet("SALARY"))
        oDbf.replace("SALARY", nOldSalary * 1.05)
    next

    nEnd        = clock()
    nUpdateTime = (nEnd - nStart) / clockspersecond()
    ? "  Updated " + nUpdates + " records in " + nUpdateTime + " seconds"
    ? "  Rate: " + floor(nUpdates / nUpdateTime) + " updates/second"

    # ---------------------------------------------------------------
    # Step 8: Read Memo Fields (1,000 reads)
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 8: Read memo fields (1,000 records) ---"

    nStart     = clock()
    nMemoReads = 1000

    for i = 1 to nMemoReads
        nRec   = (i * 11) % nRecords + 1
        oDbf.goTo(nRec)
        cNotes = oDbf.fieldGet("NOTES")
    next

    nEnd      = clock()
    nMemoTime = (nEnd - nStart) / clockspersecond()
    ? "  Read " + nMemoReads + " memo fields in " + nMemoTime + " seconds"
    ? "  Rate: " + floor(nMemoReads / nMemoTime) + " reads/second"

    # ---------------------------------------------------------------
    # Step 9: Export All to List
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 9: Export all to list ---"

    nStart = clock()
    aAll   = oDbf.toList()
    nEnd   = clock()
    nExportTime = (nEnd - nStart) / clockspersecond()
    ? "  Exported " + len(aAll) + " records in " + nExportTime + " seconds"

    # ---------------------------------------------------------------
    # Step 10: Delete 500 Records and Pack
    # ---------------------------------------------------------------

    ? ""
    ? "--- Step 10: Delete 500 records and pack (DBF + FPT) ---"

    nStart   = clock()
    nDeletes = 500

    for i = 1 to nDeletes
        nRec = (i * 19) % nRecords + 1
        oDbf.goTo(nRec)
        oDbf.deleteRec()
    next

    nDeleteTime = clock()
    ? "  Marked " + nDeletes + " records for deletion in " +
      ((nDeleteTime - nStart) / clockspersecond()) + " seconds"

    nPackStart = clock()
    oDbf.pack()
    nEnd       = clock()
    nPackTime  = (nEnd - nPackStart) / clockspersecond()
    ? "  Pack completed in " + nPackTime + " seconds"
    ? "  Records after pack: " + oDbf.recCount()

    # ---------------------------------------------------------------
    # Close and Summary
    # ---------------------------------------------------------------

    oDbf.close()

    ? ""
    ? "=============================================="
    ? "  Performance Test Summary"
    ? "=============================================="
    ? ""
    ? "  Insert 10,000 records : " + nInsertTime  + " sec (" + floor(nRecords   / nInsertTime)  + " rec/sec)"
    ? "  Sequential read all   : " + nReadTime    + " sec (" + floor(nCount     / nReadTime)    + " rec/sec)"
    ? "  Random access (1000)  : " + nRandomTime  + " sec (" + floor(nReads     / nRandomTime)  + " reads/sec)"
    ? "  Update (1000)         : " + nUpdateTime  + " sec (" + floor(nUpdates   / nUpdateTime)  + " rec/sec)"
    ? "  Memo read (1000)      : " + nMemoTime    + " sec (" + floor(nMemoReads / nMemoTime)    + " reads/sec)"
    ? "  Export to list        : " + nExportTime  + " sec"
    ? "  Pack (DBF+FPT)        : " + nPackTime    + " sec"
    ? ""
    ? "=============================================="
    ? "  Test completed!"
    ? "=============================================="

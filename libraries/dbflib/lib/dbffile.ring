/*
**  =============================================================
**  Ring Library for Processing DBF and FPT Files
**  (Visual FoxPro compatible)
**  =============================================================
*/

load "constants.rh"

class DBFFile

    cFilePath       = ""
    cFptPath        = ""
    pFile           = NULL
    pFptFile        = NULL

    nVersion        = 0x30
    nRecCount       = 0
    nHeaderSize     = 0
    nRecordSize     = 0
    lHasMemo        = false
    nCodePage       = C_CODEPAGE_WIN_1252

    aFields         = []
    nFieldCount     = 0

    # aFieldIndex: list of [UPPERCASED_NAME, field_position] pairs,
    # built once by buildFieldIndex() after fields are loaded/created.
    aFieldIndex     = []

    nCurrentRec     = 0
    lEof            = true
    lBof            = true

    cRecordBuffer   = ""
    lDeleted        = false
    lModified       = false

    nFptNextBlock   = 0
    nFptBlockSize   = 64

    lReadOnly       = false

    # ===========================================================
    # Code Page Methods
    # ===========================================================

    func setCodePage pCodePage
        nCodePage = pCodePage
        if pFile != NULL and !lReadOnly
            writeDBFHeader()
        ok

    func getCodePage
        return nCodePage

    func getCodePageName
        switch nCodePage
        on C_CODEPAGE_NONE      return "None"
        on C_CODEPAGE_DOS_437   return "DOS USA (CP 437)"
        on C_CODEPAGE_DOS_850   return "DOS International (CP 850)"
        on C_CODEPAGE_DOS_852   return "DOS Eastern European (CP 852)"
        on C_CODEPAGE_DOS_865   return "DOS Nordic (CP 865)"
        on C_CODEPAGE_DOS_866   return "DOS Russian (CP 866)"
        on C_CODEPAGE_DOS_861   return "DOS Icelandic (CP 861)"
        on C_CODEPAGE_DOS_857   return "DOS Turkish (CP 857)"
        on C_CODEPAGE_DOS_737   return "DOS Greek (CP 737)"
        on C_CODEPAGE_DOS_863   return "DOS French Canadian (CP 863)"
        on C_CODEPAGE_MAC_ROMAN return "Macintosh Roman"
        on C_CODEPAGE_WIN_1252  return "Windows ANSI (CP 1252)"
        on C_CODEPAGE_WIN_874   return "Windows/DOS Thai (CP 874)"
        on C_CODEPAGE_WIN_1250  return "Windows Central European (CP 1250)"
        on C_CODEPAGE_WIN_1251  return "Windows Cyrillic (CP 1251)"
        on C_CODEPAGE_WIN_1253  return "Windows Greek (CP 1253)"
        on C_CODEPAGE_WIN_1254  return "Windows Turkish (CP 1254)"
        on C_CODEPAGE_WIN_1255  return "Windows Hebrew (CP 1255)"
        on C_CODEPAGE_WIN_1256  return "Windows Arabic (CP 1256)"
        on C_CODEPAGE_WIN_1257  return "Windows Baltic (CP 1257)"
        other                   return "Unknown (0x" + hex(nCodePage) + ")"
        off

    # ===========================================================
    # open()
    # ===========================================================

    func open pPath

        cFilePath = pPath

        pFile = fopen(cFilePath, "rb+")
        if pFile = NULL
            pFile = fopen(cFilePath, "rb")
            if pFile = NULL
                raise("DBFLib Error: Cannot open file: " + cFilePath)
            ok
            lReadOnly = true
        ok

        readDBFHeader()
        readFieldDescriptors()
        buildFieldIndex()

        if lHasMemo
            openFptFile()
        ok

        if nRecCount > 0
            goTop()
        else
            lEof        = true
            lBof        = true
            nCurrentRec = 0
        ok

        return true

    # ===========================================================
    # create()
    # ===========================================================

    func create pPath, pFieldDefs

        nDefCount = len(pFieldDefs)
        if nDefCount = 0
            raise("DBFLib Error: No fields defined")
        ok

        cFilePath   = pPath
        aFields     = []
        aFieldIndex = []
        nFieldCount = 0
        lHasMemo    = false
        nRecordSize = 1

        for x = 1 to nDefCount

            cFName = upper(pFieldDefs[x][1])
            if len(cFName) > 10
                cFName = substr(cFName, 1, 10)
            ok

            cFType = upper(pFieldDefs[x][2])
            if len(cFType) > 1
                cFType = substr(cFType, 1, 1)
            ok

            nFLen = pFieldDefs[x][3]

            # Memo/binary fields are always 4 bytes (FoxPro binary block pointer)
            if cFType = "M" or cFType = "G"
                nFLen = 4
            ok

            add(aFields, [cFName, cFType, nFLen, 0, nRecordSize])

            nFDefLen = len(pFieldDefs[x])
            if nFDefLen >= 4
                aFields[x][FLD_DEC] = pFieldDefs[x][4]
            ok

            nRecordSize = nRecordSize + aFields[x][FLD_LEN]
            nFieldCount = nFieldCount + 1

            if cFType = "M" or cFType = "G"
                lHasMemo = true
            ok

        next

        buildFieldIndex()

        nRecCount   = 0
        nCurrentRec = 0
        lEof        = true
        lBof        = true

        if lHasMemo
            nVersion    = C_DBF_VERSION_FOXPRO
            nHeaderSize = 32 + (32 * nFieldCount) + 1 + 263   # VFP + backlink
        else
            nVersion    = C_DBF_VERSION_DBASE3
            nHeaderSize = 32 + (32 * nFieldCount) + 1
        ok

        pFile = fopen(cFilePath, "wb+")
        if pFile = NULL
            raise("DBFLib Error: Cannot create file: " + cFilePath)
        ok

        writeDBFHeader()
        writeFieldDescriptors()

        # Write EOF marker immediately after the header area
        fwrite(pFile, char(C_DBF_EOF_MARKER))
        fflush(pFile)

        if lHasMemo
            createFptFile()
        ok

        return true

    # ===========================================================
    # close()
    # ===========================================================

    func close

        if lModified
            flushRecord()
        ok

        if pFile != NULL
            writeDBFHeader()
            fclose(pFile)
            pFile = NULL
        ok

        if pFptFile != NULL
            fclose(pFptFile)
            pFptFile = NULL
        ok

    # ===========================================================
    # Navigation
    # ===========================================================

    func goTop

        if lModified
            flushRecord()
        ok

        if nRecCount = 0
            lEof        = true
            lBof        = true
            nCurrentRec = 0
            return
        ok

        nCurrentRec = 1
        lEof        = false
        lBof        = true
        readRecord(nCurrentRec)

    func goBottom

        if lModified
            flushRecord()
        ok

        if nRecCount = 0
            lEof        = true
            lBof        = true
            nCurrentRec = 0
            return
        ok

        nCurrentRec = nRecCount
        lEof        = false
        lBof        = false
        readRecord(nCurrentRec)

    func goTo pRec

        if lModified
            flushRecord()
        ok

        if pRec < 1 or pRec > nRecCount
            if pRec < 1
                lBof        = true
                nCurrentRec = 0
            else
                lEof        = true
                nCurrentRec = nRecCount + 1
            ok
            return
        ok

        nCurrentRec = pRec
        lEof        = false
        lBof        = (pRec = 1)
        readRecord(nCurrentRec)

    func skip pCount

        if lModified
            flushRecord()
        ok

        nNewRec = nCurrentRec + pCount

        if nNewRec < 1
            nCurrentRec = 0
            lBof        = true
            lEof        = false
            return
        ok

        if nNewRec > nRecCount
            nCurrentRec = nRecCount + 1
            lEof        = true
            lBof        = false
            return
        ok

        nCurrentRec = nNewRec
        lEof        = false
        lBof        = (nCurrentRec = 1)
        readRecord(nCurrentRec)

    func isEof
        return lEof

    func isBof
        return lBof

    func recNo
        return nCurrentRec

    func recCount
        return nRecCount

    func isDeleted
        return lDeleted

    # ===========================================================
    # Field Access
    # ===========================================================

    func fieldGet pFieldName

        nIdx = findFieldIndex(pFieldName)
        if nIdx = 0
            raise("DBFLib Error: Field not found: " + pFieldName)
        ok
        return getFieldValue(nIdx)

    func fieldPut pFieldName, pValue

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok

        nIdx = findFieldIndex(pFieldName)
        if nIdx = 0
            raise("DBFLib Error: Field not found: " + pFieldName)
        ok

        setFieldValue(nIdx, pValue)
        lModified = true

    func fieldName pIdx
        if pIdx < 1 or pIdx > nFieldCount return "" ok
        return aFields[pIdx][FLD_NAME]

    func fieldType pIdx
        if pIdx < 1 or pIdx > nFieldCount return "" ok
        return aFields[pIdx][FLD_TYPE]

    func fieldLen pIdx
        if pIdx < 1 or pIdx > nFieldCount return 0 ok
        return aFields[pIdx][FLD_LEN]

    func fieldDec pIdx
        if pIdx < 1 or pIdx > nFieldCount return 0 ok
        return aFields[pIdx][FLD_DEC]

    func fieldCount
        return nFieldCount

    # ===========================================================
    # Record Operations
    # ===========================================================

    func append

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok

        if lModified
            flushRecord()
        ok

        nRecCount     = nRecCount + 1
        nCurrentRec   = nRecCount
        cRecordBuffer = copy(" ", nRecordSize)

        # Zero-initialise memo / binary / integer fields.
        for x = 1 to nFieldCount
            cFT = aFields[x][FLD_TYPE]
            if cFT = "M" or cFT = "G" or cFT = "I" or cFT = "B"
                nStart = aFields[x][FLD_OFFSET] + 1   
                nLen   = aFields[x][FLD_LEN]
                cBefore = ""
                if nStart > 1
                    cBefore = substr(cRecordBuffer, 1, nStart - 1)
                ok
                cAfter        = substr(cRecordBuffer, nStart + nLen)
                cRecordBuffer = cBefore + copy(char(0), nLen) + cAfter
            ok
        next

        lDeleted  = false
        lModified = true
        lEof      = false
        if nRecCount = 1
            lBof = true
        ok

    func deleteRec

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok
        if nCurrentRec < 1 or nCurrentRec > nRecCount return ok
        lDeleted  = true
        lModified = true

    func recall

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok
        if nCurrentRec < 1 or nCurrentRec > nRecCount return ok
        lDeleted  = false
        lModified = true

    func blank

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok
        if nCurrentRec < 1 or nCurrentRec > nRecCount return ok
        if lDeleted
            cRecordBuffer = char(C_DBF_RECORD_DELETED) + copy(" ", nRecordSize - 1)
        else
            cRecordBuffer = copy(" ", nRecordSize)
        ok
        lModified = true

    func replace pFieldName, pValue
        fieldPut(pFieldName, pValue)

    # ===========================================================
    # Search
    #
    # locate()     - always searches from record 1
    # locateNext() - continues from the record AFTER the current one
    # ===========================================================

    func locate pFieldName, pValue

        if lModified flushRecord() ok

        for x = 1 to nRecCount
            readRecord(x)
            nCurrentRec = x
            cVal = fieldGet(pFieldName)
            if isString(pValue)
                if trim(cVal) = trim(pValue)
                    lEof = false
                    lBof = (x = 1)
                    return true
                ok
            else
                if number(trim(cVal)) = pValue
                    lEof = false
                    lBof = (x = 1)
                    return true
                ok
            ok
        next

        lEof        = true
        nCurrentRec = nRecCount + 1
        return false

    func locateNext pFieldName, pValue

        if lModified flushRecord() ok

        nStartRec = nCurrentRec + 1
        if nStartRec > nRecCount
            lEof = true
            return false
        ok

        for x = nStartRec to nRecCount
            readRecord(x)
            nCurrentRec = x
            cVal = fieldGet(pFieldName)
            if isString(pValue)
                if trim(cVal) = trim(pValue)
                    lEof = false
                    lBof = (x = 1)
                    return true
                ok
            else
                if number(trim(cVal)) = pValue
                    lEof = false
                    lBof = (x = 1)
                    return true
                ok
            ok
        next

        lEof        = true
        nCurrentRec = nRecCount + 1
        return false

    # ===========================================================
    # Memo Fields
    #
    # Memo (M) and General (G) fields are handled transparently:
    # fieldGet() / fieldPut() / replace() work on memo fields
    # exactly like any other field type.
    #
    # memoRead() and memoWrite() remain available as explicit
    # aliases for callers who prefer to be intentional about FPT
    # access. Both routes produce identical results.
    #
    # NOTE: every write appends a new FPT block. Repeated updates
    # to the same memo field leave orphaned blocks. Call pack() or
    # packFpt() to reclaim that space.
    # ===========================================================

    func memoRead pFieldName

        nIdx = findFieldIndex(pFieldName)
        if nIdx = 0
            raise("DBFLib Error: Field not found: " + pFieldName)
        ok

        if aFields[nIdx][FLD_TYPE] != "M" and aFields[nIdx][FLD_TYPE] != "G"
            raise("DBFLib Error: Field is not a memo field: " + pFieldName)
        ok

        if pFptFile = NULL
            return ""
        ok

        cBlockData = getRawFieldValue(nIdx)

        if cBlockData = copy(char(0), 4)
            return ""
        ok

        nBlockNum = bytes2Long(cBlockData)
        if nBlockNum <= 0
            return ""
        ok

        return readFptBlock(nBlockNum)

    func memoWrite pFieldName, pText

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok

        nIdx = findFieldIndex(pFieldName)
        if nIdx = 0
            raise("DBFLib Error: Field not found: " + pFieldName)
        ok

        if aFields[nIdx][FLD_TYPE] != "M" and aFields[nIdx][FLD_TYPE] != "G"
            raise("DBFLib Error: Field is not a memo field: " + pFieldName)
        ok

        if pFptFile = NULL
            raise("DBFLib Error: No FPT file open")
        ok

        nBlockNum = writeFptBlock(pText)
        setRawFieldValue(nIdx, long2Bytes(nBlockNum))
        lModified = true

    # ===========================================================
    # Pack
    #
    # (A) Removes deleted DBF records by rewriting the .dbf to a
    #     temp file then renaming it over the original.
    # (B) When the table has memo fields, calls packFpt() to
    #     rewrite the .fpt, dropping all orphaned blocks and
    #     updating the block-pointer bytes in every surviving
    #     record.
    # Both steps use temp-file + rename for crash safety.
    # ===========================================================

    func pack

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok

        if lModified flushRecord() ok

        # ----------------------------------------------------------
        # Step A: compact the DBF — remove deleted records
        # ----------------------------------------------------------
        cTempPath = cFilePath + ".tmp"
        pTemp     = fopen(cTempPath, "wb+")
        if pTemp = NULL
            raise("DBFLib Error: Cannot create temp file for pack: " + cTempPath)
        ok

        # Collect surviving (non-deleted) record buffers.
        aGoodRecs = []
        for x = 1 to nRecCount
            readRecord(x)
            if ! lDeleted
                add(aGoodRecs, cRecordBuffer)
            ok
        next
        nGoodCount = len(aGoodRecs)

        # Copy the original header area into the temp file
        fseek(pFile, 0, 0)
        cHeaderData = fread(pFile, nHeaderSize)
        fwrite(pTemp, cHeaderData)

        # Write surviving records
        for x = 1 to nGoodCount
            fwrite(pTemp, aGoodRecs[x])
        next
        fwrite(pTemp, char(C_DBF_EOF_MARKER))
        fflush(pTemp)
        fclose(pTemp)

        # Replace original DBF with the temp file
        fclose(pFile)
        pFile = NULL
        remove(cFilePath)
        rename(cTempPath, cFilePath)

        # Reopen the DBF
        pFile = fopen(cFilePath, "rb+")
        if pFile = NULL
            raise("DBFLib Error: Cannot reopen file after pack: " + cFilePath)
        ok

        nRecCount = nGoodCount
        writeDBFHeader()
        fflush(pFile)

        # ----------------------------------------------------------
        # Step B: compact the FPT if this table has memo fields
        # ----------------------------------------------------------
        if lHasMemo and pFptFile != NULL
            packFpt()
        ok

        if nRecCount > 0
            goTop()
        else
            nCurrentRec = 0
            lEof        = true
            lBof        = true
        ok

    # ===========================================================
    # packFpt()
    #
    # Rewrites the .fpt file keeping only the memo blocks that are
    # referenced by the surviving (non-deleted) DBF records.
    #
    # Algorithm:
    #  1. Walk every surviving record. For each memo/G field read
    #     the memo text via readFptBlock().
    #  2. Write a fresh FPT temp file from block 8 onward.
    #  3. For each memo text, writeFptBlock() into the temp FPT and
    #     note the new block number.
    #  4. Patch the DBF record buffer with the new block pointer and
    #     write the record back to disk.
    #  5. Close and rename the temp FPT over the original.
    #  6. Reopen the FPT.
    #
    # Called automatically by pack(). Can also be called standalone
    # after heavy memo-update workloads without deleting records.
    # ===========================================================

    func packFpt

        if lReadOnly
            raise("DBFLib Error: File is read-only")
        ok

        if pFptFile = NULL
            return
        ok

        if lModified flushRecord() ok

        # Collect the indices of all memo/G fields once
        aMemoFieldIdx = []
        for f = 1 to nFieldCount
            cFT = aFields[f][FLD_TYPE]
            if cFT = "M" or cFT = "G"
                add(aMemoFieldIdx, f)
            ok
        next
        nMemoFields = len(aMemoFieldIdx)

        # Nothing to do if no memo fields (shouldn't happen but be safe)
        if nMemoFields = 0 return ok

        # Open the temp FPT
        cFptTempPath = cFptPath + ".tmp"
        pFptTemp     = fopen(cFptTempPath, "wb+")
        if pFptTemp = NULL
            raise("DBFLib Error: Cannot create temp FPT file: " + cFptTempPath)
        ok

        # Write a fresh FPT header to the temp file.
        # Block 8 is the first data block (blocks 0-7 = 512-byte header).
        nNewNextBlock = 8
        nBSize        = nFptBlockSize

        # Write the 512-byte FPT header
        cFptTempHeader  = ""
        cFptTempHeader += long2BytesBE(nNewNextBlock)
        cFptTempHeader += copy(char(0), 2)
        cFptTempHeader += short2BytesBE(nBSize)
        cFptTempHeader += copy(char(0), 512 - 8)
        fwrite(pFptTemp, cFptTempHeader)

        # Walk every surviving record, re-write its memo blocks into
        # the temp FPT, and patch the DBF record with new pointers.
        for x = 1 to nRecCount
            readRecord(x)
            nCurrentRec = x

            # For each memo field in this record
            for m = 1 to nMemoFields
                nFIdx = aMemoFieldIdx[m]

                # Read the current raw block pointer (4 bytes, little-endian)
                cRawPtr   = getRawFieldValue(nFIdx)
                nOldBlock = bytes2Long(cRawPtr)

                # Determine the new block number (where we will write in temp FPT)
                nNewBlock = nNewNextBlock

                if nOldBlock > 0
                    # Read the existing memo text from the original FPT
                    cMemoText = readFptBlock(nOldBlock)
                else
                    cMemoText = ""
                ok

                # Write the memo text into the temp FPT
                nTextLen    = len(cMemoText)
                nOffset     = nNewBlock * nBSize
                fseek(pFptTemp, nOffset, 0)
                fwrite(pFptTemp, long2BytesBE(C_FPT_MEMO_TYPE))
                fwrite(pFptTemp, long2BytesBE(nTextLen))
                if nTextLen > 0
                    fwrite(pFptTemp, cMemoText)
                ok

                # Pad to block boundary
                nTotalBytes = 8 + nTextLen
                nBlocksUsed = dbf_ceil(nTotalBytes / nBSize)
                if nBlocksUsed < 1 nBlocksUsed = 1 ok
                nPadding    = (nBlocksUsed * nBSize) - nTotalBytes
                if nPadding > 0
                    fwrite(pFptTemp, copy(char(0), nPadding))
                ok

                # Advance the next-free-block pointer
                nNewNextBlock = nNewBlock + nBlocksUsed

                # Patch the DBF record buffer with the new block pointer
                # Only update if the pointer actually changed
                if nNewBlock != nOldBlock
                    setRawFieldValue(nFIdx, long2Bytes(nNewBlock))
                    lModified = true
                ok
            next

            # Flush the (possibly patched) record back to the DBF
            if lModified
                flushRecord()
            ok

        next

        fflush(pFptTemp)

        # Update the next-free-block in the temp FPT header
        fseek(pFptTemp, 0, 0)
        cUpdatedHeader  = ""
        cUpdatedHeader += long2BytesBE(nNewNextBlock)
        cUpdatedHeader += copy(char(0), 2)
        cUpdatedHeader += short2BytesBE(nBSize)
        cUpdatedHeader += copy(char(0), 512 - 8)
        fwrite(pFptTemp, cUpdatedHeader)
        fflush(pFptTemp)
        fclose(pFptTemp)

        # Replace the original FPT with the temp file
        fclose(pFptFile)
        pFptFile = NULL
        remove(cFptPath)
        rename(cFptTempPath, cFptPath)

        # Reopen the FPT
        pFptFile = fopen(cFptPath, "rb+")
        if pFptFile = NULL
            raise("DBFLib Error: Cannot reopen FPT after packFpt: " + cFptPath)
        ok

        # Update in-memory state to match the new FPT
        nFptNextBlock = nNewNextBlock

    # ===========================================================
    # Export
    # ===========================================================

    func toList

        if lModified flushRecord() ok

        aResult  = []
        nSaveRec = nCurrentRec

        for x = 1 to nRecCount
            readRecord(x)
            nCurrentRec = x
            if lDeleted loop ok
            aRow = []
            for y = 1 to nFieldCount
                add(aRow, getFieldValue(y))
            next
            add(aResult, aRow)
        next

        if nSaveRec >= 1 and nSaveRec <= nRecCount
            goTo(nSaveRec)
        ok

        return aResult

    # Returns a list of records; each record is a list of [FieldName, Value] pairs.
    # This is NOT a hash map — it is a list of 2-element lists.
    func toMapList

        if lModified flushRecord() ok

        aResult  = []
        nSaveRec = nCurrentRec

        for x = 1 to nRecCount
            readRecord(x)
            nCurrentRec = x
            if lDeleted loop ok
            aRow = []
            for y = 1 to nFieldCount
                add(aRow, [aFields[y][FLD_NAME], getFieldValue(y)])
            next
            add(aResult, aRow)
        next

        if nSaveRec >= 1 and nSaveRec <= nRecCount
            goTo(nSaveRec)
        ok

        return aResult

    func getStructure

        aResult = []
        for x = 1 to nFieldCount
            add(aResult, [aFields[x][FLD_NAME], aFields[x][FLD_TYPE],
                          aFields[x][FLD_LEN],  aFields[x][FLD_DEC]])
        next
        return aResult

    func copyStructure pNewPath
        oNew = new DBFFile
        return oNew.create(pNewPath, getStructure())

    # ===========================================================
    # Info
    # ===========================================================

    func info

        cResult  = "DBF File Information" + nl
        cResult += "====================" + nl
        cResult += "File     : " + cFilePath + nl
        cResult += "Version  : 0x" + hex(nVersion) + nl
        cResult += "Records  : " + nRecCount + nl
        cResult += "Fields   : " + nFieldCount + nl
        cResult += "Header   : " + nHeaderSize + " bytes" + nl
        cResult += "RecSize  : " + nRecordSize + " bytes" + nl
        cResult += "CodePage : " + getCodePageName() + nl

        if lHasMemo
            cResult += "Has Memo : Yes" + nl
        else
            cResult += "Has Memo : No" + nl
        ok

        if lReadOnly
            cResult += "Read Only: Yes" + nl
        else
            cResult += "Read Only: No" + nl
        ok

        cResult += nl
        cResult += "Field Structure:" + nl
        cResult += "-------------------------------------------------" + nl
        cResult += dbf_padRight("Name", 12) + dbf_padRight("Type", 6) +
                   dbf_padRight("Len",  8)  + dbf_padRight("Dec",  6) + nl
        cResult += "-------------------------------------------------" + nl

        for x = 1 to nFieldCount
            cResult += dbf_padRight(aFields[x][FLD_NAME], 12) +
                       dbf_padRight(aFields[x][FLD_TYPE], 6)  +
                       dbf_padRight("" + aFields[x][FLD_LEN], 8) +
                       dbf_padRight("" + aFields[x][FLD_DEC], 6) + nl
        next

        return cResult

    # ===========================================================
    # INTERNAL: Header I/O
    # ===========================================================

    func readDBFHeader

        fseek(pFile, 0, 0)
        cHeader = fread(pFile, 32)

        if len(cHeader) < 32
            raise("DBFLib Error: Invalid DBF header (too short)")
        ok

        nVersion    = ascii(cHeader[1])
        nRecCount   = bytes2Long(substr(cHeader, 5, 4))
        nHeaderSize = bytes2Short(substr(cHeader, 9, 2))
        nRecordSize = bytes2Short(substr(cHeader, 11, 2))
        nCodePage   = ascii(cHeader[30])

        lHasMemo = (nVersion = C_DBF_VERSION_DBASE3_MEMO) or
                   (nVersion = C_DBF_VERSION_DBASE4_MEMO) or
                   (nVersion = C_DBF_VERSION_FOXPRO_MEMO) or
                   (dbf_bitand(nVersion, 0x80) != 0)

    func writeDBFHeader

        fseek(pFile, 0, 0)

        cHeader = ""

        # Byte 1 (0-based: 0): Version
        cHeader += char(nVersion)

        # Bytes 2-4 (0-based: 1-3): Last-update date YY MM DD.
        # Ring's date() returns "dd/mm/yyyy" (positions 1-based):
        #   day   = substr(cToday, 1, 2)
        #   month = substr(cToday, 4, 2)
        #   year  = right(cToday, 4)   i.e. substr(cToday, 7, 4)
        # Ring has no year()/month()/day() functions.
        cToday  = date()
        cHeader += char(number(substr(cToday, 7, 4)) - 1900)   # YY
        cHeader += char(number(substr(cToday, 4, 2)))           # MM
        cHeader += char(number(substr(cToday, 1, 2)))           # DD

        # Bytes 5-8 (0-based: 4-7): Record count (little-endian 32-bit)
        cHeader += long2Bytes(nRecCount)

        # Bytes 9-10 (0-based: 8-9): Header size (little-endian 16-bit)
        cHeader += short2Bytes(nHeaderSize)

        # Bytes 11-12 (0-based: 10-11): Record size (little-endian 16-bit)
        cHeader += short2Bytes(nRecordSize)

        # Bytes 13-14 (0-based: 12-13): Reserved
        cHeader += char(0) + char(0)

        # Byte 15 (0-based: 14): Incomplete transaction flag
        cHeader += char(0)

        # Byte 16 (0-based: 15): Encryption flag
        cHeader += char(0)

        # Bytes 17-28 (0-based: 16-27): Reserved for multi-user dBASE
        cHeader += copy(char(0), 12)

        # Byte 29 (0-based: 28): Table flags (bit 1 set = has memo)
        if lHasMemo
            cHeader += char(0x02)
        else
            cHeader += char(0)
        ok

        # Byte 30 (0-based: 29): Language driver ID (code page)
        cHeader += char(nCodePage)

        # Bytes 31-32 (0-based: 30-31): Reserved
        cHeader += char(0) + char(0)

        fwrite(pFile, cHeader)
        fflush(pFile)

    func readFieldDescriptors

        aFields     = []
        nFieldCount = 0
        fseek(pFile, 32, 0)
        nRecordOffset = 1

        while true

            cByte = fread(pFile, 1)
            if len(cByte) = 0 exit ok
            if ascii(cByte) = C_DBF_HEADER_TERMINATOR exit ok

            cRest      = fread(pFile, 31)
            cFieldData = cByte + cRest

            if len(cFieldData) < 32 exit ok

            # Field name: positions 1-11 (1-based), null-terminated
            cTempName = ""
            for k = 1 to 11
                if ascii(cFieldData[k]) = 0 exit ok
                cTempName += cFieldData[k]
            next

            cType = cFieldData[12]
            nLen  = ascii(cFieldData[17])
            nDec  = ascii(cFieldData[18])

            # Character fields store length across two bytes
            if cType = "C"
                nLen = ascii(cFieldData[17]) + ascii(cFieldData[18]) * 256
                nDec = 0
            ok

            add(aFields, [upper(trim(cTempName)), cType, nLen, nDec, nRecordOffset])

            nRecordOffset += nLen
            nFieldCount++

            if cType = "M" or cType = "G"
                lHasMemo = true
            ok

        end

    func writeFieldDescriptors

        fseek(pFile, 32, 0)

        nOffset = 1

        for x = 1 to nFieldCount

            cDesc      = ""
            cFieldName = aFields[x][FLD_NAME]
            nNameLen   = len(cFieldName)

            # Field name: 11 bytes, null-padded
            cDesc += cFieldName
            cDesc += copy(char(0), 11 - nNameLen)

            # Type: 1 byte
            cDesc += aFields[x][FLD_TYPE]

            # Record displacement (4 bytes, little-endian) — VFP format
            cDesc += long2Bytes(nOffset)
            nOffset += aFields[x][FLD_LEN]

            # Length: 1 byte
            cDesc += char(aFields[x][FLD_LEN])

            # Decimals: 1 byte
            cDesc += char(aFields[x][FLD_DEC])

            # Field flags: 1 byte (0 = normal)
            cDesc += char(0)

            # Reserved: 13 bytes
            cDesc += copy(char(0), 13)

            fwrite(pFile, cDesc)
        next

        # Header terminator byte
        fwrite(pFile, char(C_DBF_HEADER_TERMINATOR))

        # VFP backlink area (263 bytes), present only when a memo file exists
        if lHasMemo
            fwrite(pFile, copy(char(0), 263))
        ok

        fflush(pFile)

    # ===========================================================
    # INTERNAL: Field index cache
    # ===========================================================

    # Builds aFieldIndex = list of [UPPERCASED_NAME, field_position].
    # Called once after fields are loaded or created.
    # Lookups scan this small list — avoids upper()/trim() on every call.
    func buildFieldIndex
        aFieldIndex = []
        for x = 1 to nFieldCount
            add(aFieldIndex, [aFields[x][FLD_NAME], x])
        next

    # ===========================================================
    # INTERNAL: Record I/O
    # ===========================================================

    func readRecord pRec

        if pRec < 1 or pRec > nRecCount return ok

        nPos          = nHeaderSize + ((pRec - 1) * nRecordSize)
        fseek(pFile, nPos, 0)
        cRecordBuffer = fread(pFile, nRecordSize)

        nBufLen = len(cRecordBuffer)
        if nBufLen < nRecordSize
            cRecordBuffer += copy(" ", nRecordSize - nBufLen)
        ok

        lDeleted  = (ascii(cRecordBuffer[1]) = C_DBF_RECORD_DELETED)
        lModified = false

    func flushRecord

        if ! lModified return ok
        if lReadOnly   return ok
        if nCurrentRec < 1 return ok

        if lDeleted
            cRecordBuffer = char(C_DBF_RECORD_DELETED) + substr(cRecordBuffer, 2)
        else
            cRecordBuffer = char(C_DBF_RECORD_ACTIVE)  + substr(cRecordBuffer, 2)
        ok

        nPos = nHeaderSize + ((nCurrentRec - 1) * nRecordSize)
        fseek(pFile, nPos, 0)
        fwrite(pFile, cRecordBuffer)

        # EOF marker follows immediately after the last record
        if nCurrentRec = nRecCount
            fwrite(pFile, char(C_DBF_EOF_MARKER))
        ok

        fflush(pFile)
        writeDBFHeader()
        lModified = false

    # ===========================================================
    # INTERNAL: Field value access
    # ===========================================================

    func findFieldIndex pName

        cSearchName = upper(trim(pName))
        nIdxCount   = len(aFieldIndex)
        for x = 1 to nIdxCount
            if aFieldIndex[x][1] = cSearchName
                return aFieldIndex[x][2]
            ok
        next
        return 0

    func getRawFieldValue pIdx

        nStart = aFields[pIdx][FLD_OFFSET] + 1   # +1 for 1-based string index
        nLen   = aFields[pIdx][FLD_LEN]
        return substr(cRecordBuffer, nStart, nLen)

    func setRawFieldValue pIdx, pValue

        nStart  = aFields[pIdx][FLD_OFFSET] + 1
        nLen    = aFields[pIdx][FLD_LEN]
        nValLen = len(pValue)

        if nValLen < nLen
            pValue += copy(" ", nLen - nValLen)
        ok
        if nValLen > nLen
            pValue = substr(pValue, 1, nLen)
        ok

        cBefore = ""
        if nStart > 1
            cBefore = substr(cRecordBuffer, 1, nStart - 1)
        ok
        cAfter        = substr(cRecordBuffer, nStart + nLen)
        cRecordBuffer = cBefore + pValue + cAfter

    func getFieldValue pIdx

        cType = aFields[pIdx][FLD_TYPE]
        cRaw  = getRawFieldValue(pIdx)

        switch cType

        on "C"
            return cRaw

        on "N"
            return trim(cRaw)

        on "F"
            return trim(cRaw)

        on "D"
            return trim(cRaw)

        on "L"
            cVal = upper(trim(cRaw))
            if cVal = "T" or cVal = "Y" or cVal = "1"
                return true
            else
                return false
            ok

        # Memo (M) and General (G) fields: read the text from the FPT file
        # transparently. fieldGet() / fieldPut() / replace() all work on
        # memo fields exactly like any other field type.
        on "M"
            return memoRead(aFields[pIdx][FLD_NAME])

        on "G"
            return memoRead(aFields[pIdx][FLD_NAME])

        on "I"
            return bytes2Long(cRaw)

        other
            return cRaw

        off

    func setFieldValue pIdx, pValue

        cType = aFields[pIdx][FLD_TYPE]
        nLen  = aFields[pIdx][FLD_LEN]
        nDec  = aFields[pIdx][FLD_DEC]

        switch cType

        on "C"
            if isNumber(pValue) pValue = "" + pValue ok
            cVal    = pValue
            nValLen = len(cVal)
            if nValLen > nLen
                cVal = substr(cVal, 1, nLen)
            else
                cVal += copy(" ", nLen - nValLen)
            ok
            setRawFieldValue(pIdx, cVal)

        on "N"
            if isString(pValue) pValue = number(pValue) ok
            if nDec > 0
                cFmt = "" + pValue
                if substr(cFmt, ".") = 0
                    cFmt += "." + copy("0", nDec)
                ok
            else
                cFmt = "" + floor(pValue)
            ok
            if len(cFmt) > nLen
                raise("DBFLib Error: Value '" + cFmt + "' is too wide for field " +
                      aFields[pIdx][FLD_NAME] + " (max " + nLen + " chars)")
            ok
            cFmt = dbf_padLeft(cFmt, nLen)
            setRawFieldValue(pIdx, cFmt)

        on "F"
            if isString(pValue) pValue = number(pValue) ok
            cFmt = "" + pValue
            if len(cFmt) > nLen
                raise("DBFLib Error: Value '" + cFmt + "' is too wide for field " +
                      aFields[pIdx][FLD_NAME] + " (max " + nLen + " chars)")
            ok
            cFmt = dbf_padLeft(cFmt, nLen)
            setRawFieldValue(pIdx, cFmt)

        on "D"
            if isNumber(pValue) pValue = "" + pValue ok
            cVal    = pValue
            nValLen = len(cVal)
            if nValLen > 8
                cVal = substr(cVal, 1, 8)
            else
                cVal += copy(" ", 8 - nValLen)
            ok
            setRawFieldValue(pIdx, cVal)

        on "L"
            if pValue = true or pValue = "T" or pValue = "t" or pValue = "Y"
                setRawFieldValue(pIdx, "T")
            else
                setRawFieldValue(pIdx, "F")
            ok

        on "M"
            # Write transparently to the FPT file via memoWrite().
            # fieldPut() / replace() work on memo fields like any other type.
            if isNumber(pValue) pValue = "" + pValue ok
            memoWrite(aFields[pIdx][FLD_NAME], pValue)

        on "G"
            if isNumber(pValue) pValue = "" + pValue ok
            memoWrite(aFields[pIdx][FLD_NAME], pValue)

        on "I"
            if isString(pValue) pValue = number(pValue) ok
            setRawFieldValue(pIdx, long2Bytes(pValue))

        other
            if isNumber(pValue) pValue = "" + pValue ok
            cVal    = pValue
            nValLen = len(cVal)
            if nValLen > nLen
                cVal = substr(cVal, 1, nLen)
            else
                cVal += copy(" ", nLen - nValLen)
            ok
            setRawFieldValue(pIdx, cVal)

        off

    # ===========================================================
    # INTERNAL: FPT (memo file) I/O
    # ===========================================================

    func openFptFile

        nPathLen  = len(cFilePath)
        cBase     = substr(cFilePath, 1, nPathLen - 4)

        aExts     = [".fpt", ".FPT"]
        nExtCount = len(aExts)

        for x = 1 to nExtCount
            cTestPath = cBase + aExts[x]
            pFptFile  = fopen(cTestPath, "rb+")
            if pFptFile != NULL
                cFptPath = cTestPath
                readFptHeader()
                return
            ok
            pFptFile = fopen(cTestPath, "rb")
            if pFptFile != NULL
                cFptPath = cTestPath
                readFptHeader()
                return
            ok
        next

        # Warn when the DBF header says there is a memo file but we cannot find it
        pFptFile = NULL
        ? "DBFLib Warning: Memo flag set but no FPT file found for: " + cFilePath

    func createFptFile

        nPathLen  = len(cFilePath)
        cBase     = substr(cFilePath, 1, nPathLen - 4)
        cFptPath  = cBase + ".fpt"

        pFptFile  = fopen(cFptPath, "wb+")
        if pFptFile = NULL
            raise("DBFLib Error: Cannot create FPT file: " + cFptPath)
        ok

        nFptBlockSize = 64
        nFptNextBlock = 8    # Blocks 0-7 (512 bytes) are the FPT header
        writeFptHeader()

    func readFptHeader

        fseek(pFptFile, 0, 0)
        cHeader = fread(pFptFile, 8)
        if len(cHeader) < 8 return ok

        nFptNextBlock = bytes2LongBE(substr(cHeader, 1, 4))
        nFptBlockSize = bytes2ShortBE(substr(cHeader, 7, 2))
        if nFptBlockSize = 0 nFptBlockSize = 64 ok

    func writeFptHeader

        fseek(pFptFile, 0, 0)

        cHeader  = ""
        cHeader += long2BytesBE(nFptNextBlock)
        cHeader += copy(char(0), 2)
        cHeader += short2BytesBE(nFptBlockSize)
        # VFP FPT header is always 512 bytes regardless of block size
        cHeader += copy(char(0), 512 - 8)

        fwrite(pFptFile, cHeader)
        fflush(pFptFile)

    func readFptBlock pBlockNum

        if pFptFile = NULL return "" ok

        nOffset = pBlockNum * nFptBlockSize
        fseek(pFptFile, nOffset, 0)

        cBlockHeader = fread(pFptFile, 8)
        if len(cBlockHeader) < 8 return "" ok

        nDataLen = bytes2LongBE(substr(cBlockHeader, 5, 4))

        if nDataLen <= 0       return "" ok
        if nDataLen > 10000000 return "" ok

        return fread(pFptFile, nDataLen)

    func writeFptBlock pText

        if pFptFile = NULL return 0 ok

        nBlockNum = nFptNextBlock
        nOffset   = nBlockNum * nFptBlockSize
        fseek(pFptFile, nOffset, 0)

        nTextLen = len(pText)
        fwrite(pFptFile, long2BytesBE(C_FPT_MEMO_TYPE))
        fwrite(pFptFile, long2BytesBE(nTextLen))
        fwrite(pFptFile, pText)

        nTotalBytes = 8 + nTextLen
        nBlocksUsed = dbf_ceil(nTotalBytes / nFptBlockSize)
        if nBlocksUsed < 1 nBlocksUsed = 1 ok

        nPadding = (nBlocksUsed * nFptBlockSize) - nTotalBytes
        if nPadding > 0
            fwrite(pFptFile, copy(char(0), nPadding))
        ok

        nFptNextBlock = nBlockNum + nBlocksUsed
        writeFptHeader()

        return nBlockNum

    # ===========================================================
    # INTERNAL: Binary encoding helpers
    # ===========================================================

    func bytes2Short pBytes
        if len(pBytes) < 2 return 0 ok
        return ascii(pBytes[1]) + ascii(pBytes[2]) * 256

    func bytes2Long pBytes
        if len(pBytes) < 4 return 0 ok
        return ascii(pBytes[1]) +
               ascii(pBytes[2]) * 256 +
               ascii(pBytes[3]) * 65536 +
               ascii(pBytes[4]) * 16777216

    func short2Bytes pVal
        return char(pVal % 256) + char(floor(pVal / 256) % 256)

    func long2Bytes pVal
        if pVal < 0 pVal = 0 ok
        return char(pVal % 256) +
               char(floor(pVal / 256)      % 256) +
               char(floor(pVal / 65536)    % 256) +
               char(floor(pVal / 16777216) % 256)

    func bytes2ShortBE pBytes
        if len(pBytes) < 2 return 0 ok
        return ascii(pBytes[1]) * 256 + ascii(pBytes[2])

    func bytes2LongBE pBytes
        if len(pBytes) < 4 return 0 ok
        return ascii(pBytes[1]) * 16777216 +
               ascii(pBytes[2]) * 65536    +
               ascii(pBytes[3]) * 256      +
               ascii(pBytes[4])

    func short2BytesBE pVal
        return char(floor(pVal / 256) % 256) + char(pVal % 256)

    func long2BytesBE pVal
        if pVal < 0 pVal = 0 ok
        return char(floor(pVal / 16777216) % 256) +
               char(floor(pVal / 65536)    % 256) +
               char(floor(pVal / 256)      % 256) +
               char(pVal % 256)

    func dbf_padLeft pStr, pWidth
        pStr = "" + pStr
        nLen = len(pStr)
        if nLen >= pWidth
            return substr(pStr, nLen - pWidth + 1, pWidth)
        ok
        return copy(" ", pWidth - nLen) + pStr

    func dbf_padRight pStr, pWidth
        pStr = "" + pStr
        nLen = len(pStr)
        if nLen >= pWidth
            return substr(pStr, 1, pWidth)
        ok
        return pStr + copy(" ", pWidth - nLen)

    func dbf_ceil pVal
        if pVal = floor(pVal) return pVal ok
        return floor(pVal) + 1

    # Bitwise AND via right-shift loop.
    # Exits as soon as either operand reaches zero (early termination).
    func dbf_bitand pA, pB
        nResult = 0
        nBit    = 1
        while pA > 0 and pB > 0
            if (pA % 2 = 1) and (pB % 2 = 1)
                nResult += nBit
            ok
            pA   = floor(pA / 2)
            pB   = floor(pB / 2)
            nBit = nBit * 2
        end
        return nResult

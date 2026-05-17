# DBFLib — Ring Language DBF/FPT Library

A pure-Ring library for reading, writing, and maintaining Visual FoxPro
`.dbf` database files and their companion `.fpt` memo files.

---

## Table of Contents

1. [Overview](#overview)
2. [File Format Compatibility](#file-format-compatibility)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Field Types](#field-types)
6. [Constants Reference](#constants-reference)
7. [API Reference](#api-reference)
   - [Opening and Creating Files](#opening-and-creating-files)
   - [Navigation](#navigation)
   - [Reading Fields](#reading-fields)
   - [Writing Fields](#writing-fields)
   - [Record Operations](#record-operations)
   - [Searching](#searching)
   - [Memo Fields](#memo-fields)
   - [Maintenance](#maintenance)
   - [Export](#export)
   - [Structure](#structure)
   - [Code Page](#code-page)
   - [Information](#information)
8. [Error Handling](#error-handling)
9. [Code Page Reference](#code-page-reference)
10. [Known Limitations](#known-limitations)
11. [Complete Example](#complete-example)

---

## Overview

DBFLib gives Ring programs full read/write access to Visual FoxPro `.dbf` and
`.fpt` files. It handles the complete file lifecycle: creating tables, appending
and updating records, soft-deleting and recalling, packing (physical removal of
deleted records), and compacting memo files to reclaim orphaned FPT blocks.

**All field types — including memo fields — are accessed through the same
uniform API.** `fieldGet()`, `fieldPut()`, and `replace()` work identically on
character, numeric, logical, date, integer, and memo fields. The library handles
FPT file I/O transparently; no special memo functions are needed for normal use.

Files produced by the library open correctly in Visual FoxPro and any
other tool that reads the Visual FoxPro file format.

---

## File Format Compatibility

| Feature | Support |
|---|---|
| Visual FoxPro `.dbf` (no memo) | Read / Write |
| Visual FoxPro `.dbf` + `.fpt` (with memo) | Read / Write |
| VFP binary memo block pointers | Yes |
| VFP 263-byte backlink area | Yes |
| FPT 64-byte block size | Yes |
| Code page / language driver byte | Yes |
| Deletion flag byte | Yes |
| EOF marker (0x1A) | Yes |

---

## Installation

	ringpm install dbflib from ringpackages

No external dependencies are required.

---

## Quick Start

```ring
load "dbflib.ring"

# --- Create a new table ---
oDbf = new DBFFile

aFields = [
    ["ID",      "N",  6, 0],
    ["NAME",    "C", 40, 0],
    ["SALARY",  "N", 12, 2],
    ["ACTIVE",  "L",  1, 0],
    ["NOTES",   "M", 10, 0]   # memo field — used just like any other
]

oDbf.create("employees.dbf", aFields)

# --- Append a record — memo field uses replace() like everything else ---
oDbf.append()
oDbf.replace("ID",     1)
oDbf.replace("NAME",   "Ahmed Al-Rashid")
oDbf.replace("SALARY", 85000.50)
oDbf.replace("ACTIVE", true)
oDbf.replace("NOTES",  "Senior developer, joined 2023.")

# --- Close and reopen ---
oDbf.close()

oDbf = new DBFFile
oDbf.open("employees.dbf")

# --- Read all records — fieldGet() works on memo fields too ---
oDbf.goTop()
while ! oDbf.isEof()
    ? trim(oDbf.fieldGet("NAME")) + " — " + oDbf.fieldGet("SALARY")
    ? oDbf.fieldGet("NOTES")
    oDbf.skip(1)
end

oDbf.close()
```

---

## Field Types

| Type Code | Description | Notes |
|---|---|---|
| `C` | Character (string) | Fixed width, space-padded on the right |
| `N` | Numeric | Stored as a formatted ASCII string |
| `F` | Float | Like N but allows scientific notation |
| `D` | Date | 8-char string in `YYYYMMDD` format |
| `L` | Logical | Stored as `T` / `F` |
| `M` | Memo | Variable-length text in `.fpt` file; transparent to caller |
| `G` | General (OLE) | Same layout as M; text content supported |
| `I` | Integer | 4-byte little-endian binary |
| `B` | Binary | Zero-initialised on append |

### Field Definition Format

When calling `create()`, each field is defined as a list with 3 or 4 elements:

```ring
[FieldName, TypeCode, Length, Decimals]   # 4-element (full)
[FieldName, TypeCode, Length]             # 3-element (decimals default to 0)
```

- **FieldName** — up to 10 characters; automatically uppercased and truncated
- **TypeCode** — one of the type codes above; only the first character is used
- **Length** — storage width in bytes (ignored for `M`/`G`, always forced to 4)
- **Decimals** — number of decimal places for `N`/`F` fields

---

## Constants Reference

### Version Flags

The two flags the library writes when creating files:

```ring
C_DBF_VERSION_FOXPRO        # 0x30  Visual FoxPro — no memo fields
C_DBF_VERSION_FOXPRO_MEMO   # 0xF5  Visual FoxPro — has memo fields
```

Additional flags recognised when reading existing files:

```ring
C_DBF_VERSION_DBASE3        # 0x03
C_DBF_VERSION_DBASE3_MEMO   # 0x83
C_DBF_VERSION_DBASE4_MEMO   # 0x8B
```

### Record Markers

```ring
C_DBF_RECORD_ACTIVE     # 0x20  space — record is active
C_DBF_RECORD_DELETED    # 0x2A  asterisk (*) — record is soft-deleted
C_DBF_EOF_MARKER        # 0x1A  end-of-file marker
C_DBF_HEADER_TERMINATOR # 0x0D  end of field descriptor list
```

### Field Sub-list Indices

When working with the list returned by `getStructure()`, use these named
indices instead of bare numbers:

```ring
FLD_NAME    # 1 — field name string
FLD_TYPE    # 2 — single-character type code
FLD_LEN     # 3 — storage length in bytes
FLD_DEC     # 4 — decimal places
FLD_OFFSET  # 5 — byte offset within the record (internal use)
```

---

## API Reference

### Opening and Creating Files

---

#### `open(pPath)` → `true`

Opens an existing `.dbf` file. If the file cannot be opened for read/write it
is opened read-only. The companion `.fpt` memo file is opened automatically
when present.

After a successful open, the current record is positioned at record 1
(`goTop()` is called internally). If the file has no records, `isEof()` and
`isBof()` are both `true`.

**Raises** if the file cannot be opened at all.

```ring
oDbf = new DBFFile
oDbf.open("customers.dbf")
```

---

#### `create(pPath, pFieldDefs)` → `true`

Creates a new `.dbf` file with the given field definitions. If any field has
type `M` or `G`, a companion `.fpt` file is created automatically.

The file version is set to `C_DBF_VERSION_DBASE3` (no memo) or
`C_DBF_VERSION_FOXPRO` (with memo). The code page defaults to
`C_CODEPAGE_WIN_1252`.

**Raises** if the field list is empty or the file cannot be created.

```ring
oDbf = new DBFFile
oDbf.create("orders.dbf", [
    ["ORDERID",  "N",  8, 0],
    ["CUSTNAME", "C", 40, 0],
    ["AMOUNT",   "N", 12, 2],
    ["ORDERDATE","D",  8, 0],
    ["NOTES",    "M", 10, 0]
])
```

---

#### `close()`

Flushes any pending record changes to disk, writes the final file header, and
closes both the `.dbf` and `.fpt` file handles. Always call `close()` when
finished; not calling it may leave the last modified record unsaved.

```ring
oDbf.close()
```

---

### Navigation

The library maintains a **current record pointer**. Navigation methods update
this pointer and load the record into an internal buffer. Two boolean flags
track boundary state:

- **BOF** (Beginning Of File) — `true` when the pointer is at or before record 1.
- **EOF** (End Of File) — `true` when the pointer is past the last record.

When both are `true` the table is empty.

---

#### `goTop()`

Moves to the first record and reads it. Sets `isBof()` = `true`,
`isEof()` = `false`. If the table is empty, sets both to `true`.

---

#### `goBottom()`

Moves to the last record and reads it. Sets `isBof()` = `false`,
`isEof()` = `false`. If the table is empty, sets both to `true`.

---

#### `goTo(pRec)`

Moves to the record at physical position `pRec` (1-based). If `pRec` is less
than 1, sets `isBof()` = `true`. If `pRec` is greater than `recCount()`, sets
`isEof()` = `true`.

---

#### `skip(pCount)`

Moves forward or backward by `pCount` records. Positive values move forward;
negative values move backward. Sets EOF or BOF if the pointer goes past the
boundaries.

```ring
oDbf.goTop()
while ! oDbf.isEof()
    # process record
    oDbf.skip(1)
end
```

---

#### `isEof()` → `true` / `false`

Returns `true` when the current position is past the last record.

---

#### `isBof()` → `true` / `false`

Returns `true` when the current position is at or before record 1, or when the
table is empty.

---

#### `recNo()` → number

Returns the 1-based physical position of the current record. Returns `0` when
at BOF and `recCount() + 1` when at EOF.

---

#### `recCount()` → number

Returns the total number of records in the table, including soft-deleted ones.

---

#### `isDeleted()` → `true` / `false`

Returns `true` if the current record has been soft-deleted with `deleteRec()`.

---

### Reading Fields

---

#### `fieldGet(pFieldName)` → value

Returns the value of the named field in the current record. Works uniformly
across all field types including memo fields.

| Field Type | Return Value |
|---|---|
| `C` | String (space-padded to field width) |
| `N`, `F` | Trimmed numeric string (e.g. `"85000.50"`) |
| `D` | Trimmed date string in `YYYYMMDD` format |
| `L` | `true` or `false` |
| `I` | Number (decoded from 4-byte little-endian binary) |
| `M`, `G` | Memo text string read from the FPT file |

Use `trim()` on `C`, `N`, `F`, and `D` values to strip padding.

**Raises** if the field name does not exist.

```ring
cName   = trim(oDbf.fieldGet("NAME"))
nSalary = number(oDbf.fieldGet("SALARY"))
lActive = oDbf.fieldGet("ACTIVE")
cDate   = oDbf.fieldGet("HIREDATE")   # e.g. "20230115"
cNotes  = oDbf.fieldGet("NOTES")      # memo — works like any other field
```

---

#### `fieldName(pIdx)` → string

Returns the name of field number `pIdx` (1-based). Returns `""` if out of range.

---

#### `fieldType(pIdx)` → string

Returns the single-character type code of field number `pIdx`.

---

#### `fieldLen(pIdx)` → number

Returns the storage length in bytes of field number `pIdx`.

---

#### `fieldDec(pIdx)` → number

Returns the number of decimal places of field number `pIdx`.

---

#### `fieldCount()` → number

Returns the total number of fields in the table.

```ring
for i = 1 to oDbf.fieldCount()
    ? oDbf.fieldName(i) + " " + oDbf.fieldType(i) + " " + oDbf.fieldLen(i)
next
```

---

### Writing Fields

---

#### `fieldPut(pFieldName, pValue)`

Sets the value of the named field in the current record. Works uniformly across
all field types including memo fields. The record is not written to disk until
the next navigation call or `close()`.

**Raises** if the field name does not exist, the file is read-only, or a
numeric value is too wide for its field.

```ring
oDbf.fieldPut("NAME",   "Sara Abdullah")
oDbf.fieldPut("SALARY", 91000.00)
oDbf.fieldPut("ACTIVE", true)
oDbf.fieldPut("NOTES",  "Project manager, joined 2021.")   # memo
```

---

#### `replace(pFieldName, pValue)`

Alias for `fieldPut()`. Provided for familiarity with FoxPro/dBASE syntax.
Identical behaviour in every respect.

```ring
oDbf.replace("NAME",   "Sara Abdullah")
oDbf.replace("SALARY", 91000.00)
oDbf.replace("NOTES",  "Updated bio.")   # memo — no special handling needed
```

---

### Record Operations

---

#### `append()`

Adds a new blank record at the end of the table and positions the current
record pointer on it. All character fields are space-filled. Memo, binary, and
integer fields are zero-filled. The record is marked as modified.

**Raises** if the file is read-only.

```ring
oDbf.append()
oDbf.replace("ID",    42)
oDbf.replace("NAME",  "Khalid Mansour")
oDbf.replace("NOTES", "New hire.")   # memo written transparently
```

---

#### `deleteRec()`

Soft-deletes the current record. The record remains in the file until `pack()`
is called.

**Raises** if the file is read-only.

---

#### `recall()`

Clears the deletion flag on the current record, restoring it to active status.

**Raises** if the file is read-only.

---

#### `blank()`

Resets all fields of the current record to their empty/default values. The
deletion flag is preserved.

**Raises** if the file is read-only.

---

### Searching

---

#### `locate(pFieldName, pValue)` → `true` / `false`

Performs a sequential search **always starting from record 1**, regardless of
the current position. Matches by trimmed string equality (for string values) or
numeric equality (for numeric values). Positions on the first match and returns
`true`. Returns `false` and sets EOF if no match is found.

```ring
if oDbf.locate("CITY", "Riyadh")
    ? "Found: " + trim(oDbf.fieldGet("NAME"))
ok
```

---

#### `locateNext(pFieldName, pValue)` → `true` / `false`

Continues a search from the record **after** the current one.

```ring
nCount = 0
if oDbf.locate("DEPT", "Engineering")
    nCount++
    while oDbf.locateNext("DEPT", "Engineering")
        nCount++
    end
ok
? "Engineering staff: " + nCount
```

---

### Memo Fields

Memo (`M`) and General (`G`) fields store variable-length text in a companion
`.fpt` file. The library handles all FPT I/O transparently:

- **`fieldGet()`** reads the memo text from the FPT file and returns it as a string.
- **`fieldPut()`** / **`replace()`** write the string to the FPT file and update
  the block pointer in the DBF record.

No special handling is needed. Use memo fields exactly like any other field.

```ring
# Write
oDbf.replace("NOTES", "Performance review completed. Rating: Excellent.")

# Read
? oDbf.fieldGet("NOTES")

# In a loop — no different from any other field
oDbf.goTop()
while ! oDbf.isEof()
    ? trim(oDbf.fieldGet("NAME")) + ": " + oDbf.fieldGet("NOTES")
    oDbf.skip(1)
end
```

#### `memoRead(pFieldName)` → string
#### `memoWrite(pFieldName, pText)`

These explicit memo functions remain available as aliases. They produce
identical results to `fieldGet()` and `replace()` respectively. Use them if
you prefer to make FPT access explicit in your code.

```ring
# These pairs are exactly equivalent:
oDbf.replace("NOTES",  "Some text")       # — preferred
oDbf.memoWrite("NOTES", "Some text")      # — explicit alias

cText = oDbf.fieldGet("NOTES")            # — preferred
cText = oDbf.memoRead("NOTES")            # — explicit alias
```

> **Note:** every write (via either API) appends a new block to the FPT file.
> Repeated updates to the same memo field accumulate orphaned blocks. Call
> `pack()` or `packFpt()` to reclaim that space.

---

### Maintenance

---

#### `pack()`

Permanently removes all soft-deleted records from the `.dbf` file. When the
table has memo fields, also calls `packFpt()` automatically to compact the
`.fpt` file and remove all orphaned blocks.

Both operations write to a temporary file first, then replace the original via
rename — safe against data loss if interrupted.

After `pack()`, the current record is positioned at record 1, or EOF/BOF if
the table is now empty.

**Raises** if the file is read-only or a temporary file cannot be created.

```ring
# Delete inactive employees and clean up both DBF and FPT
oDbf.goTop()
while ! oDbf.isEof()
    if ! oDbf.fieldGet("ACTIVE")
        oDbf.deleteRec()
    ok
    oDbf.skip(1)
end
oDbf.pack()
? "Records after pack: " + oDbf.recCount()
```

---

#### `packFpt()`

Compacts the `.fpt` memo file independently of the DBF record list. Rewrites
only the memo blocks referenced by records currently in the table, discarding
all orphaned blocks. Updates the block pointers in every affected DBF record
on disk.

Use `packFpt()` standalone after a heavy memo-update workload where no records
have been deleted (in those cases `pack()` calls `packFpt()` automatically).

**Raises** if the file is read-only or a temporary file cannot be created.
Does nothing if no FPT file is open.

```ring
# After many replace("NOTES", ...) calls with no record deletions
oDbf.packFpt()
```

---

### Export

---

#### `toList()` → list of lists

Returns all non-deleted records as a list of rows. Each row is a list of field
values in field-definition order. Memo fields are included as their text
content, just like any other field. The current record position is preserved.

```ring
aData = oDbf.toList()
nRows = len(aData)
for i = 1 to nRows
    ? aData[i][2]   # NAME (field 2)
    ? aData[i][7]   # NOTES memo text (field 7)
next
```

---

#### `toMapList()` → list of lists of pairs

Returns all non-deleted records as a list of rows, where each row is a list of
`[FieldName, Value]` pairs. Memo field values are included as text. The current
record position is preserved.

```ring
aMap = oDbf.toMapList()
for i = 1 to len(aMap)
    aRow = aMap[i]
    for j = 1 to len(aRow)
        ? aRow[j][1] + " = " + aRow[j][2]
    next
next
```

---

### Structure

---

#### `getStructure()` → list of field definitions

Returns the field definitions in the same format accepted by `create()`. Each
element is `[Name, Type, Length, Decimals]`.

```ring
aStruct = oDbf.getStructure()
for i = 1 to len(aStruct)
    ? aStruct[i][FLD_NAME] + " " + aStruct[i][FLD_TYPE] +
      "(" + aStruct[i][FLD_LEN] + ")"
next
```

---

#### `copyStructure(pNewPath)` → `true`

Creates a new empty `.dbf` file at `pNewPath` with the same field definitions
as the current table.

```ring
oDbf.copyStructure("employees_backup.dbf")
```

---

### Code Page

---

#### `setCodePage(pCodePage)`

Sets the language driver / code page byte in the DBF header. Use the
`C_CODEPAGE_*` constants.

```ring
oDbf.setCodePage(C_CODEPAGE_WIN_1256)   # Windows Arabic
```

---

#### `getCodePage()` → number

Returns the current code page constant value.

---

#### `getCodePageName()` → string

Returns a human-readable description of the current code page.

```ring
? oDbf.getCodePageName()   # e.g. "Windows Arabic (CP 1256)"
```

---

### Information

---

#### `info()` → string

Returns a formatted multi-line string describing the file: path, version,
record count, field count, header size, record size, code page, memo flag,
read-only flag, and a field structure table.

```ring
? oDbf.info()
```

Example output:

```
DBF File Information
====================
File     : employees.dbf
Version  : 0x30
Records  : 10
Fields   : 7
Header   : 360 bytes
RecSize  : 97 bytes
CodePage : Windows ANSI (CP 1252)
Has Memo : Yes
Read Only: No

Field Structure:
-------------------------------------------------
Name        Type  Len     Dec
-------------------------------------------------
ID          N     6       0
NAME        C     30      0
CITY        C     20      0
SALARY      N     12      2
HIREDATE    D     8       0
ACTIVE      L     1       0
NOTES       M     4       0
```

---

## Error Handling

All errors are raised using Ring's `raise()` mechanism. Wrap calls in
`try / catch / done` blocks to handle them:

```ring
try
    oDbf.open("missing.dbf")
catch
    ? "Could not open file: " + cCatchError
done
```

Common error messages:

| Message | Cause |
|---|---|
| `DBFLib Error: Cannot open file: <path>` | File not found or no read permission |
| `DBFLib Error: Cannot create file: <path>` | No write permission or invalid path |
| `DBFLib Error: File is read-only` | Write attempted on a read-only file |
| `DBFLib Error: Field not found: <name>` | Field name does not exist in the table |
| `DBFLib Error: Field is not a memo field: <name>` | `memoRead()`/`memoWrite()` called on a non-memo field |
| `DBFLib Error: No FPT file open` | Memo write attempted but FPT could not be found or created |
| `DBFLib Error: Value '...' is too wide for field <name>` | Numeric value exceeds field width |
| `DBFLib Error: Invalid DBF header (too short)` | File is corrupt or not a DBF file |
| `DBFLib Error: No fields defined` | `create()` called with an empty field list |
| `DBFLib Warning: Memo flag set but no FPT found` | Printed (not raised) when no `.fpt` companion file is found beside the `.dbf` |

---

## Code Page Reference

| Constant | Value | Description |
|---|---|---|
| `C_CODEPAGE_NONE` | `0x00` | No code page |
| `C_CODEPAGE_DOS_437` | `0x01` | DOS USA |
| `C_CODEPAGE_DOS_850` | `0x02` | DOS International |
| `C_CODEPAGE_WIN_1252` | `0x03` | Windows ANSI *(default)* |
| `C_CODEPAGE_MAC_ROMAN` | `0x04` | Macintosh Roman |
| `C_CODEPAGE_DOS_865` | `0x08` | DOS Nordic |
| `C_CODEPAGE_DOS_852` | `0x64` | DOS Eastern European |
| `C_CODEPAGE_DOS_857` | `0x65` | DOS Turkish |
| `C_CODEPAGE_DOS_737` | `0x66` | DOS Greek |
| `C_CODEPAGE_DOS_866` | `0x67` | DOS Russian |
| `C_CODEPAGE_DOS_862` | `0x68` | DOS Hebrew |
| `C_CODEPAGE_DOS_864` | `0x69` | DOS Arabic |
| `C_CODEPAGE_WIN_1250` | `0x78` | Windows Central European |
| `C_CODEPAGE_WIN_1251` | `0x79` | Windows Cyrillic |
| `C_CODEPAGE_WIN_1253` | `0x7A` | Windows Greek |
| `C_CODEPAGE_WIN_1254` | `0x7B` | Windows Turkish |
| `C_CODEPAGE_WIN_1255` | `0x7C` | Windows Hebrew |
| `C_CODEPAGE_WIN_1256` | `0x7D` | Windows Arabic |
| `C_CODEPAGE_WIN_1257` | `0x7E` | Windows Baltic |
| `C_CODEPAGE_WIN_874` | `0x7F` | Windows Thai |

---

## Known Limitations

**No FPT block reuse on write.** Every call to `replace()` (or `memoWrite()`)
on a memo field appends a new block to the FPT file. The previous block becomes
orphaned. Call `pack()` or `packFpt()` periodically to reclaim the space.

**No index file support.** `locate()` and `locateNext()` always perform a full
sequential scan. For keyed random access on large tables, build an in-memory
index from `toList()`.

**No transaction support.** Each navigation call or `close()` writes the
current record directly to disk with no rollback capability.

**Date fields are strings.** Date values are stored and returned as 8-character
`YYYYMMDD` strings. The library does not validate, convert, or compute dates.

**Single-user access.** The library does not implement multi-user locking.

---

## Complete Example

```ring
load "dbflib.ring"

# -------------------------------------------------------
# 1. Create a table
# -------------------------------------------------------
oDbf = new DBFFile
oDbf.create("staff.dbf", [
    ["ID",      "N",  6, 0],
    ["NAME",    "C", 30, 0],
    ["DEPT",    "C", 20, 0],
    ["SALARY",  "N", 12, 2],
    ["ACTIVE",  "L",  1, 0],
    ["BIO",     "M", 10, 0]
])

# -------------------------------------------------------
# 2. Insert records — replace() works on all field types
# -------------------------------------------------------
aStaff = [
    [1, "Ahmed Al-Rashid", "Engineering", 85000.00, true,  "Lead engineer."],
    [2, "Fatima Hassan",   "HR",          72000.00, true,  "HR director."],
    [3, "Omar bin Said",   "Finance",     65000.00, false, "Contract ended."],
    [4, "Sara Abdullah",   "Engineering", 91000.00, true,  "VP Engineering."]
]

nCount = len(aStaff)
for i = 1 to nCount
    r = aStaff[i]
    oDbf.append()
    oDbf.replace("ID",     r[1])
    oDbf.replace("NAME",   r[2])
    oDbf.replace("DEPT",   r[3])
    oDbf.replace("SALARY", r[4])
    oDbf.replace("ACTIVE", r[5])
    oDbf.replace("BIO",    r[6])   # memo — no special function needed
next

# -------------------------------------------------------
# 3. Read all records — fieldGet() works on all field types
# -------------------------------------------------------
? "=== All Staff ==="
oDbf.goTop()
while ! oDbf.isEof()
    ? trim(oDbf.fieldGet("NAME")) + " (" + trim(oDbf.fieldGet("DEPT")) + ")"
    ? "  Bio: " + oDbf.fieldGet("BIO")   # memo — same as any other field
    oDbf.skip(1)
end

# -------------------------------------------------------
# 4. Search
# -------------------------------------------------------
? ""
? "=== Engineering Department ==="
if oDbf.locate("DEPT", "Engineering")
    ? trim(oDbf.fieldGet("NAME"))
    while oDbf.locateNext("DEPT", "Engineering")
        ? trim(oDbf.fieldGet("NAME"))
    end
ok

# -------------------------------------------------------
# 5. Update — replace() on a memo field works like any field
# -------------------------------------------------------
oDbf.goTo(1)
oDbf.replace("SALARY", 90000.00)
oDbf.replace("BIO",    "Lead engineer. Promoted 2024.")

# -------------------------------------------------------
# 6. Export — toList() includes memo content automatically
# -------------------------------------------------------
aAll = oDbf.toList()
? ""
? "Exported " + len(aAll) + " records"
? "Record 1 BIO: " + aAll[1][6]   # memo text in column 6

# -------------------------------------------------------
# 7. Delete inactive staff and pack (compacts DBF + FPT)
# -------------------------------------------------------
oDbf.goTop()
while ! oDbf.isEof()
    if ! oDbf.fieldGet("ACTIVE")
        oDbf.deleteRec()
    ok
    oDbf.skip(1)
end
oDbf.pack()
? "Records after pack: " + oDbf.recCount()

# -------------------------------------------------------
# 8. Set code page and show info
# -------------------------------------------------------
oDbf.setCodePage(C_CODEPAGE_WIN_1256)
? ""
? oDbf.info()

# -------------------------------------------------------
# 9. Copy structure to a new file
# -------------------------------------------------------
oDbf.copyStructure("staff_archive.dbf")

# -------------------------------------------------------
# 10. Close
# -------------------------------------------------------
oDbf.close()
```

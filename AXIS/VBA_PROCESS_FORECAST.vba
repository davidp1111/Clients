'VBA_PROCESS_FORECAST.vba 2024-09-03_2009
Sub ProcessForecastNoDtw()
    Dim conn As Object
    Dim configSheet As Worksheet
    Dim xmlCreds As Worksheet
    Dim processPath As String
    
    Dim logMessage As String
    logMessage = "----------------------------------------------" & vbCrLf & _
                 "Start Forecast Process:  " & Format(Now, "mm/dd/yyyy HH:MM:SS")
    WriteToLogFile logMessage
    
    Call CheckLicenseExpiration
    
    Call GitHubSqlXml
    
    ' Reference to the XML_CREDENTIALS worksheet
    Set configSheet = ThisWorkbook.Sheets("XML_CREDENTIALS")
    
    ' Reference to the XML_CREDENTIALS worksheet
    Set xmlCreds = ThisWorkbook.Sheets("XML_CREDENTIALS")
    
    ' Get the process path from the XML_CREDENTIALS sheet
    Dim lastRow As Long
    Dim i As Long
    
    lastRow = configSheet.Cells(configSheet.Rows.Count, "A").End(xlUp).row
    
    ' Find the DTW.exe path
    processPath = "" ' Reset the processPath
    For i = 1 To lastRow
        If configSheet.Range("A" & i).Value = "DTWEXE" Then
            processPath = configSheet.Range("B" & i).Value
            Exit For
        End If
    Next i

    ' Check if the path was found
    If processPath = "" Then
        MsgBox "DTW.exe path not found in the XML_CREDENTIALS sheet.", vbExclamation
    End If
    
    ' Initialize ADODB connection object
    Set conn = CreateObject("ADODB.Connection")
    
    ' Process each section (LEADTIME, MINMAX, FORECAST)
    Call ProcessSection("LEADTIME", configSheet, xmlCreds, conn, processPath)
    Call ProcessSection("MINMAX", configSheet, xmlCreds, conn, processPath)
    Call ProcessSection("FORECAST", configSheet, xmlCreds, conn, processPath)
    
    logMessage = "End Forecast Process: " & Format(Now, "mm/dd/yyyy HH:MM:SS")
    WriteToLogFile logMessage
    
    MsgBox "End Forecast Process"
    
Cleanup:
    ' Clean up
    On Error Resume Next
    conn.Close
    Set conn = Nothing
    
    Exit Sub
    
ConnectionError:
    MsgBox "Connection failed: " & Err.Description
    GoTo Cleanup
End Sub

Sub ProcessSection(sectionName As String, configSheet As Worksheet, xmlCreds As Worksheet, conn As Object, processPath As String)
    Dim sqlfilePath As String
    Dim sqlfile2Path As String
    Dim xmlfilePath As String
    Dim dtwFilePath As String
    Dim dtwFile2Path As String
    Dim sheetsSql As Worksheet
    Dim sheets2Sql As Worksheet
    Dim sheetsXml As Worksheet
    Dim parameters As String
    Dim userName As String
    Dim password As String
    Dim lastRow As Long
    Dim i As Long
    
    ' Get the current user's name
    Dim currentUser As String
    currentUser = Environ("Username")
    
    ' Get the base paths from the XML_CREDENTIALS worksheet and replace %User% with the current user
    Dim sqlPath As String
    Dim xmlPath As String
    Dim dtwPath As String
    Dim basePath As String
    Dim j As Long
    
    lastRow = configSheet.Cells(configSheet.Rows.Count, "A").End(xlUp).row
    
    ' Find the Import Folders path
    For j = 1 To lastRow
        If configSheet.Range("A" & j).Value = "ImportFolders" Then
            basePath = configSheet.Range("B" & j).Value
            Exit For
        End If
    Next j
    
    ' If Import Folders is found, construct the paths
    If basePath <> "" Then
        basePath = Replace(basePath, "%Username%", currentUser)
        sqlPath = basePath & "\FILES_SQL\"
        xmlPath = basePath & "\FILES_XML\"
        dtwPath = basePath & "\FILES_DTW\"
    Else
        MsgBox "Import Folders path not found in the XML_CREDENTIALS sheet.", vbExclamation
    End If

    
    ' Define the file paths
    sqlfilePath = sqlPath & "SQL_" & sectionName & ".txt"
    sqlfile2Path = sqlPath & "SQL_FORECAST_OFCT.txt"
    xmlfilePath = xmlPath & "XML_" & sectionName & ".xml"
    dtwFilePath = dtwPath & "DTW_" & sectionName & ".txt"
    dtwFile2Path = dtwPath & "DTW_FORECAST_OFCT.txt"
    
    ' Reference the corresponding sheets
    Set sheetsSql = ThisWorkbook.Sheets("SQL_" & sectionName)
    Set sheetsXml = ThisWorkbook.Sheets("XML_" & sectionName)
    Set sheets2Sql = ThisWorkbook.Sheets("SQL_FORECAST_OFCT")
    
    ' Get credentials
    lastRow = xmlCreds.Cells(xmlCreds.Rows.Count, "A").End(xlUp).row
    
    For i = 1 To lastRow
        If xmlCreds.Range("A" & i).Value = "UserName" Then
            userName = xmlCreds.Range("B" & i).Value
        ElseIf xmlCreds.Range("A" & i).Value = "Password" Then
            password = xmlCreds.Range("B" & i).Value
        End If
    Next i
    
    ' Call the subroutine to write the SQL sheet to the text file
    Call WriteSqlToFile(sheetsSql, sqlfilePath)
    Call WriteSqlToFile(sheets2Sql, sqlfile2Path)
    
    ' Create the XML file with replacements, passing dtwFilePath for %Temp% replacement
    Call CreateXMLFileWithReplacements(sheetsXml, xmlCreds, xmlfilePath, dtwFilePath, dtwFile2Path, userName, password)
    
    ' Call the subroutine to execute the SQL query and write to the DTW text file
    Call ExecuteSQLAndWriteToFile(conn, sqlfilePath, dtwFilePath, xmlCreds)
    Call ExecuteSQLAndWriteToFile(conn, sqlfile2Path, dtwFile2Path, xmlCreds)
    
    ' Set parameters for the process
    parameters = xmlPath & "XML_" & sectionName & ".xml"
    
    ' Call the RunDTW subroutine with the processPath and parameters
    ' Call RunDTW(processPath, parameters, sqlfilePath, sqlfile2Path, dtwFilePath, dtwFile2Path, xmlfilePath)
    
    'MsgBox sectionName & " completed successfully.", vbInformation
End Sub

Sub WriteSqlToFile(sheetToWrite As Worksheet, filePath As String)
    Dim txtFile As Integer
    Dim outputLine As String
    Dim i As Long
    Dim j As Long
    Dim folderPath As String
    
    ' Extract folder path from the file path
    folderPath = Left(filePath, InStrRev(filePath, "\"))
    
    ' Check if the folder exists, and create it if it doesn't
    If Dir(folderPath, vbDirectory) = "" Then
        MkDir folderPath
    End If
    
    ' Open the text file for writing
    txtFile = FreeFile
    Open filePath For Output As txtFile
    
    ' Write the content of the specified sheet to the text file
    For i = 1 To sheetToWrite.UsedRange.Rows.Count
        outputLine = ""
        For j = 1 To sheetToWrite.UsedRange.Columns.Count
            If j > 1 Then outputLine = outputLine & vbTab
            outputLine = outputLine & sheetToWrite.Cells(i, j).Value
        Next j
        Print #txtFile, outputLine
    Next i
    
    ' Close the text file
    Close txtFile
End Sub

Sub ExecuteSQLAndWriteToFile(conn As Object, queryFilePath As String, dtwFilePath As String, xmlCreds As Worksheet)
    Dim rs As Object
    Dim sqlQuery As String
    Dim fileNum As Integer
    Dim lineText As String
    Dim txtFile As Integer
    Dim outputLine As String
    Dim i As Integer
    Dim dsn As String, UID As String, pwd As String
    Dim folderPath As String
    Dim lastRow As Long
    Dim j As Long
    
    ' Read the SQL query from the text file
    fileNum = FreeFile
    Open queryFilePath For Input As fileNum
    Do Until EOF(fileNum)
        Line Input #fileNum, lineText
        sqlQuery = sqlQuery & lineText & vbCrLf
    Loop
    Close fileNum
    
    ' Build the connection string using values from XML_CREDENTIALS
    lastRow = xmlCreds.Cells(xmlCreds.Rows.Count, "A").End(xlUp).row
    
    For j = 1 To lastRow
        Select Case xmlCreds.Range("A" & j).Value
            Case "DSN"
                dsn = xmlCreds.Range("B" & j).Value
            Case "UID"
                UID = xmlCreds.Range("B" & j).Value
            Case "PWD"
                pwd = xmlCreds.Range("B" & j).Value
        End Select
    Next j
    
    conn.ConnectionString = "DSN=" & dsn & ";UID=" & UID & ";PWD=" & pwd & ";"
    
    ' Test the connection
    On Error GoTo ConnectionError
    conn.Open
    
    ' Execute the SQL query
    Set rs = conn.Execute(sqlQuery)
    
    ' Check if the recordset is empty
    If rs.EOF And rs.BOF Then
        MsgBox "No records returned by the query."
        GoTo Cleanup
    End If
    
    ' Extract folder path from the dtwFilePath
    folderPath = Left(dtwFilePath, InStrRev(dtwFilePath, "\"))
    
    ' Check if the folder exists, and create it if it doesn't
    If Dir(folderPath, vbDirectory) = "" Then
        MkDir folderPath
    End If
    
    ' Open the text file for writing DTW_LEADTIME.txt
    txtFile = FreeFile
    Open dtwFilePath For Output As txtFile
    
    ' Write headers to the text file
    outputLine = ""
    For i = 0 To rs.Fields.Count - 1
        If i > 0 Then outputLine = outputLine & vbTab
        outputLine = outputLine & rs.Fields(i).Name
    Next i
    Print #txtFile, outputLine
    
    ' Loop through the recordset and write to the text file
    Do Until rs.EOF
        outputLine = ""
        For i = 0 To rs.Fields.Count - 1
            If i > 0 Then outputLine = outputLine & vbTab
            outputLine = outputLine & rs.Fields(i).Value
        Next i
        Print #txtFile, outputLine
        rs.MoveNext
    Loop
    
    ' Close the text file
    Close txtFile
    
Cleanup:
    ' Clean up
    On Error Resume Next
    rs.Close
    conn.Close
    Set rs = Nothing
    Exit Sub
    
ConnectionError:
    MsgBox "Connection failed: " & Err.Description
    GoTo Cleanup
End Sub

Sub CreateXMLFileWithReplacements(sheet As Worksheet, xmlCreds As Worksheet, filePath As String, dtwFilePath As String, dtwFile2Path As String, userName As String, password As String)
    Dim xmlFile As Integer
    Dim i As Long
    Dim xmlLine As String
    Dim folderPath As String
    
    ' Retrieve credentials from XML_CREDENTIALS sheet
    Dim company As String, server As String, lastRow As Long, k As Long
    lastRow = xmlCreds.Cells(xmlCreds.Rows.Count, "A").End(xlUp).row

    For k = 1 To lastRow
        Select Case xmlCreds.Range("A" & k).Value
            Case "Company"
                company = xmlCreds.Range("B" & k).Value
            Case "Server"
                server = xmlCreds.Range("B" & k).Value
        End Select
    Next k
    
    ' Extract folder path from the file path
    folderPath = Left(filePath, InStrRev(filePath, "\"))
    
    ' Check if the folder exists, and create it if it doesn't
    If Dir(folderPath, vbDirectory) = "" Then
        MkDir folderPath
    End If
    
    ' Open the XML file for writing
    xmlFile = FreeFile
    Open filePath For Output As xmlFile
    
    ' Loop through each row in the sheet and replace placeholders
    For i = 1 To sheet.UsedRange.Rows.Count
        xmlLine = sheet.Cells(i, 1).Value
        xmlLine = Replace(xmlLine, "%UserName%", userName)
        xmlLine = Replace(xmlLine, "%Password%", password)
        xmlLine = Replace(xmlLine, "%Company%", company)
        xmlLine = Replace(xmlLine, "%Server%", server)
        xmlLine = Replace(xmlLine, "%Temp%", dtwFilePath) ' Replace %Temp% with dtwFilePath
        xmlLine = Replace(xmlLine, "%Temp2%", dtwFile2Path) ' Replace %Temp2% with dtwFile2Path
        Print #xmlFile, xmlLine
    Next i
    
    ' Close the XML file
    Close xmlFile
End Sub

Sub RunDTW(processPath As String, parameters As String, sqlfilePath As String, sqlfile2Path As String, dtwFilePath As String, dtwFile2Path As String, xmlfilePath As String)
    Dim wsh As Object
    Dim execResult As Long
    Dim command As String
    
    ' Build the command
    command = Chr(34) & processPath & Chr(34) & " -s " & Chr(34) & parameters & Chr(34)
    
    ' Create the WScript.Shell object
    Set wsh = CreateObject("WScript.Shell")
    
    ' Execute the command
    execResult = wsh.Run(command, 1, True)
    
    ' Optional: Handle the result if needed
    If execResult = 0 Then
        Kill sqlfilePath
        Kill sqlfile2Path
        Kill dtwFilePath
        Kill dtwFile2Path
        Kill xmlfilePath
        'MsgBox "RunDTW completed successfully.", vbInformation
    Else
        MsgBox "Process failed with exit code: " & execResult, vbExclamation
    End If
    
    Call CopyLastOLOGRowToLogFile
    
End Sub

Sub WriteToLogFile(logText As String)
    Dim logFilePath As String
    Dim userName As String
    Dim finalPath As String
    Dim logFileNumber As Integer
    Dim configSheet As Worksheet
    Dim lastRow As Long
    Dim i As Long

    ' Reference the XML_CREDENTIALS worksheet
    Set configSheet = ThisWorkbook.Sheets("XML_CREDENTIALS")
    
    ' Find the row with "Import Folder" in column A
    lastRow = configSheet.Cells(configSheet.Rows.Count, "A").End(xlUp).row
    logFilePath = ""
    
    For i = 1 To lastRow
    If configSheet.Range("A" & i).Value = "ImportFolders" Then
            logFilePath = configSheet.Range("B" & i).Value
            Exit For
        End If
    Next i
    
    ' Ensure the log file path is not empty
    If Trim(logFilePath) = "" Then
        MsgBox "Log file path corresponding to 'Import Folder' in column A is empty. Please provide a valid path.", vbExclamation
        Exit Sub
    End If
    
    ' Get the username
    userName = Environ("Username")
    
    ' Replace %Username% with the actual username
    logFilePath = Replace(logFilePath, "%Username%", userName)
    
    ' Define the folder path where the log file will be stored
    logFolder = logFilePath & "\Logs"
    
    ' Check if the folder exists, and create it if it doesn't
    If Dir(logFolder, vbDirectory) = "" Then
        MkDir logFolder
    End If
    
    ' Append \Logs\DTWLogResults.txt to the path
    finalPath = logFilePath & "\Logs\DTWLogResults.txt"
    
    ' Get the next available file number
    logFileNumber = FreeFile
    
    ' Open the log file for appending
    On Error GoTo ErrorHandler
    Open finalPath For Append As #logFileNumber
    
    ' Write the log text to the file
    Print #logFileNumber, logText
    
    ' Close the file
    Close #logFileNumber
    Exit Sub
    
ErrorHandler:
    MsgBox "An error occurred while writing to the log file: " & Err.Description, vbCritical
    Close #logFileNumber
End Sub

Sub CopyLastOLOGRowToLogFile()
    Dim dbPath As String
    Dim conn As Object
    Dim rs As Object
    Dim sql As String
    Dim logFilePath As String
    Dim userName As String
    Dim finalPath As String
    Dim logFileNumber As Integer
    Dim header As String
    Dim lastRow As String
    Dim i As Integer
    Dim columnWidths() As Integer
    Dim configSheet As Worksheet
    Dim pathRow As Long
    
    ' Reference the XML_CREDENTIALS worksheet
    Set configSheet = ThisWorkbook.Sheets("XML_CREDENTIALS")
    
    ' Attempt to find the row containing "Import Folders" in Column A
    On Error Resume Next
    pathRow = Application.WorksheetFunction.Match("Import Folders", configSheet.Columns("A"), 0)
    On Error GoTo 0
    
     ' Check if the match was found
    If IsError(pathRow) Then
        MsgBox "Import Folder not found in XML_CREDENTIALS sheet.", vbExclamation
        Exit Sub
    End If
    
    ' Retrieve the path from Column B
    dbPath = configSheet.Cells(pathRow, 2).Value
    
    ' Get the username
    userName = Environ("Username")
    
    ' Replace %Username% with the actual username
    dbPath = Replace(dbPath, "%Username%", userName)
    
    ' Construct the log file path (replace %Username% with actual username)
    logFilePath = dbPath & "\Logs\DTWLogResults.txt"
    
    ' Define the path to the Access database
    dbPath = dbPath & "\dtw.mdb"

    ' SQL to get the last row from the OLOG table
    sql = "SELECT * FROM OLOG ORDER BY LogID DESC"

    ' Create a connection to the Access database
    Set conn = CreateObject("ADODB.Connection")
    conn.Open "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=" & dbPath & ";"

    ' Execute the query and open the recordset
    Set rs = CreateObject("ADODB.Recordset")
    rs.Open sql, conn, 3, 1
    
    ' Initialize columnWidths array based on the number of fields
    ReDim columnWidths(rs.Fields.Count - 1)
    
    ' Determine the maximum width for each column
    For i = 0 To rs.Fields.Count - 1
        columnWidths(i) = Len(rs.Fields(i).Name)
    Next i

    ' Move to the first row to check the data lengths
    rs.MoveFirst
    Do Until rs.EOF
        For i = 0 To rs.Fields.Count - 1
            If Len(rs.Fields(i).Value) > columnWidths(i) Then
                columnWidths(i) = Len(rs.Fields(i).Value)
            End If
        Next i
        rs.MoveNext
    Loop
    
    ' Reset the recordset to the first row
    rs.MoveFirst
    
    ' Get the header with aligned columns
    For i = 0 To rs.Fields.Count - 1
        header = header & PadRight(rs.Fields(i).Name, columnWidths(i) + 2)
    Next i
    
    ' Check if the recordset is not empty
    If Not rs.EOF Then
        ' Get the last row with aligned columns
        For i = 0 To rs.Fields.Count - 1
            lastRow = lastRow & PadRight(rs.Fields(i).Value, columnWidths(i) + 2)
        Next i
        
        ' Get the next available file number
        logFileNumber = FreeFile
        
        ' Open the log file for appending
        On Error GoTo ErrorHandler
        Open logFilePath For Append As #logFileNumber
        
        ' Write the header before each row
        Print #logFileNumber, header
        Print #logFileNumber, lastRow
        
        ' Close the file
        Close #logFileNumber
    End If
    
    ' Clean up
    rs.Close
    conn.Close
    Set rs = Nothing
    Set conn = Nothing
    Exit Sub

ErrorHandler:
    MsgBox "An error occurred: " & Err.Description, vbCritical
    If logFileNumber <> 0 Then Close #logFileNumber
    If Not rs Is Nothing Then rs.Close
    If Not conn Is Nothing Then conn.Close
    Set rs = Nothing
    Set conn = Nothing
End Sub

Function PadRight(ByVal text As String, ByVal totalWidth As Integer) As String
    PadRight = text & Space(totalWidth - Len(text))
End Function

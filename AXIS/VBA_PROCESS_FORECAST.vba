-- AXIS/VBA_PROCESS_FORECAST.vba
Sub RunSQLFromFile()
    Dim conn As Object
    Dim configSheet As Worksheet
    Dim xmlCreds As Worksheet
    Dim processPath As String
    
    ' Reference to the CONFIG worksheet
    Set configSheet = ThisWorkbook.Sheets("CONFIG")
    
    ' Reference to the XML_CREDENTIALS worksheet
    Set xmlCreds = ThisWorkbook.Sheets("XML_CREDENTIALS")
    
    ' Get the process path from the CONFIG sheet
    processPath = configSheet.Range("B7").Value
    
    ' Initialize ADODB connection object
    Set conn = CreateObject("ADODB.Connection")
    
    ' Process each section (LEADTIME, MINMAX, FORECAST)
    Call ProcessSection("LEADTIME", configSheet, xmlCreds, conn, processPath)
    Call ProcessSection("MINMAX", configSheet, xmlCreds, conn, processPath)
    Call ProcessSection("FORECAST", configSheet, xmlCreds, conn, processPath)
    
    MsgBox "Complete"
    
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
    
    ' Get the base paths from the CONFIG worksheet
    Dim sqlPath As String: sqlPath = configSheet.Range("B3").Value
    Dim xmlPath As String: xmlPath = configSheet.Range("B4").Value
    Dim dtwPath As String: dtwPath = configSheet.Range("B5").Value
    
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
    userName = xmlCreds.Range("B6").Value
    password = xmlCreds.Range("B7").Value
    
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
    Call RunDTW(processPath, parameters, sqlfilePath, sqlfile2Path, dtwFilePath, dtwFile2Path, xmlfilePath)
    
    'MsgBox sectionName & " completed successfully.", vbInformation
End Sub

Sub WriteSqlToFile(sheetToWrite As Worksheet, filePath As String)
    Dim txtFile As Integer
    Dim outputLine As String
    Dim i As Long
    Dim j As Long
    
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
    Dim dsn As String, uid As String, pwd As String
    
    ' Read the SQL query from the text file
    fileNum = FreeFile
    Open queryFilePath For Input As fileNum
    Do Until EOF(fileNum)
        Line Input #fileNum, lineText
        sqlQuery = sqlQuery & lineText & vbCrLf
    Loop
    Close fileNum
    
    ' Build the connection string using values from XML_CREDENTIALS
    dsn = xmlCreds.Range("B1").Value
    uid = xmlCreds.Range("B2").Value
    pwd = xmlCreds.Range("B3").Value
    
    conn.ConnectionString = "DSN=" & dsn & ";UID=" & uid & ";PWD=" & pwd & ";"
    
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
    
    ' Retrieve credentials from XML_CREDENTIALS sheet
    Dim company As String, server As String
    company = xmlCreds.Range("B4").Value
    server = xmlCreds.Range("B5").Value
    
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
        xmlLine = Replace(xmlLine, "%Temp%", dtwFilePath) ' Replace %Temp% with dtwfilePath
        xmlLine = Replace(xmlLine, "%Temp2%", dtwFile2Path) ' Replace %Temp% with dtwfilePath
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
End Sub

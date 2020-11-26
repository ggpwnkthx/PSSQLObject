# PSSQLObject
Simplifies SQL Queries based on Key and Referential Constraints

# Usage
## Construct
### Windows Credentials
```
$SQL = [PSSQLObject]::new("address.to.server", "Database Name")
```
### SQL Credentials (with dialog)
```
$Credential = Get-Credential
$SQL = [PSSQLObject]::new("address.to.server", "Database Name", $Credential)
```
### SQL Credentials (without dialog)
```
$Password = "PassWord" | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "UserName", $Password
$SQL = [PSSQLObject]::new("address.to.server", "Database Name", $Credential)
```
## Methods
### Query()
The Query method will return an array with the results.

NOTE: The Query method is only limited to the user's permissions. Be careful!
```
$SQL.Query("SELECT * FROM [sys].[certificates]") | Foreach { 
    $SQL.Query("UPDATE [sys].[certificates] SET name = 'This_is_a_terrible_mistake' WHERE certificate_id = "+$_.certificate_id)
}
```
### Cache()
The Cache methods build a query and stores the results locally based on 4 paramerters: table name, column name, comparator, and the value to compare. However, there are also 3 overload methods that simplify and broaden the results.

The results are not returned, but rather stored in the ```Tables``` property.
```
$SQL.Cache("table_name", "column_name", "=", "1234")
$SQL.Tables.table_name | Where-Object { $_.column_name -eq "1234" }
```
### Get()
The Get method will return a record that has been cached. If the record is not found it will attempt to cache the record and will return it.
```
$SQL.Get("table_name","column_name","1234").other_column
```
## Relationships
The PSSQLObject constructor will check for Key columns and Referential Constrains to detect relationships between columns in different tables. The Query method will replace any column value that has a relationship with a ```PSSQLLink``` object. The ```PSSQLLink``` object stores the references to the ```PSSQLObject``` and the relationship logistics. To access the targeted relative, use the ```Target``` method.
### Target()
The Target method will run the ```Get()``` method from the reference to the ```PSSQLObject``` with it's relationship logicistcs.  
```
$SQL.Get("table_name","column_name","1234").relative_column.Target().column_of_relative
```
